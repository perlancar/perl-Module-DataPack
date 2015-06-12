package Module::DataPack;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(datapack_modules);

our %SPEC;

my $mod_re    = qr/\A[A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)*\z/;
my $mod_pm_re = qr!\A[A-Za-z_][A-Za-z0-9_]*(/[A-Za-z_][A-Za-z0-9_]*)*\.pm\z!;

$SPEC{datapack_modules} = {
    v => 1.1,
    summary => 'Like Module::FatPack, but uses datapacking instead of fatpack',
    description => <<'_',

Both this module and `Module:FatPack` generate source code that embeds modules'
source codes and load them on-demand via require hook. The difference is that
the modules' source codes are put in `__DATA__` section instead of regular Perl
hashes (fatpack uses `%fatpacked`). This reduces compilation overhead, although
this is not noticeable unless when the number of embedded modules is quite
large. For example, in `App::pause`, the `pause` script embeds ~320 modules with
a total of ~54000 lines. The overhead of fatpack code is about 49ms, while with
datapack the overhead is about XXX ms.

There are two downsides of this technique. The major one is that you cannot load
modules during BEGIN phase (e.g. using `use`) because at that point, DATA
section is not yet available. You can only use run-time require()'s.

Another downside of this technique is that you cannot use `__DATA__` section for
other purposes (well, actually with some care, you still can).

_
    args_rels => {
        req_one => ['module_names', 'module_srcs'],
        'dep_any&' => [
            [stripper_maintain_linum => ['stripper']],
            [stripper_ws             => ['stripper']],
            [stripper_comment        => ['stripper']],
            [stripper_pod            => ['stripper']],
            [stripper_log            => ['stripper']],
        ],
    },
    args => {
        module_names => {
            summary => 'Module names to search',
            schema  => ['array*', of=>['str*', match=>$mod_re], min_len=>1],
            tags => ['category:input'],
            pos => 0,
            greedy => 1,
            'x.schema.element_entity' => 'modulename',
            cmdline_aliases => {m=>{}},
        },
        module_srcs => {
            summary => 'Module source codes (a hash, keys are module names)',
            schema  => ['hash*', {
                each_key=>['str*', match=>$mod_re],
                each_value=>['str*'],
                min_len=>1,
            }],
            tags => ['category:input'],
        },
        preamble => {
            summary => 'Perl source code to add before the datapack code',
            schema => 'str*',
            tags => ['category:input'],
        },
        postamble => {
            summary => 'Perl source code to add after the datapack code'.
                ' (but before the __DATA__ section)',
            schema => 'str*',
            tags => ['category:input'],
        },

        output => {
            summary => 'Output filename',
            schema => 'str*',
            cmdline_aliases => {o=>{}},
            tags => ['category:output'],
            'x.schema.entity' => 'filename',
        },
        overwrite => {
            summary => 'Whether to overwrite output if previously exists',
            'summary.alt.bool.yes' => 'Overwrite output if previously exists',
            schema => [bool => default => 0],
            tags => ['category:output'],
        },

        stripper => {
            summary => 'Whether to strip included modules using Perl::Stripper',
            'summary.alt.bool.yes' => 'Strip included modules using Perl::Stripper',
            schema => ['bool' => default=>0],
            tags => ['category:stripping'],
        },
        stripper_maintain_linum => {
            summary => "Set maintain_linum=1 in Perl::Stripper",
            schema => ['bool'],
            default => 0,
            tags => ['category:stripping'],
            description => <<'_',

Only relevant when stripping using Perl::Stripper.

_
        },
        stripper_ws => {
            summary => "Set strip_ws=1 (strip whitespace) in Perl::Stripper",
            'summary.alt.bool.not' => "Set strip_ws=0 (don't strip whitespace) in Perl::Stripper",
            schema => ['bool'],
            default => 1,
            tags => ['category:stripping'],
            description => <<'_',

Only relevant when stripping using Perl::Stripper.

_
        },
        stripper_comment => {
            summary => "Set strip_comment=1 (strip comments) in Perl::Stripper",
            'summary.alt.bool.not' => "Set strip_comment=0 (don't strip comments) in Perl::Stripper",
            schema => ['bool'],
            default => 1,
            description => <<'_',

Only relevant when stripping using Perl::Stripper.

_
            tags => ['category:stripping'],
        },
        stripper_pod => {
            summary => "Set strip_pod=1 (strip POD) in Perl::Stripper",
            'summary.alt.bool.not' => "Set strip_pod=0 (don't strip POD) in Perl::Stripper",
            schema => ['bool'],
            default => 1,
            tags => ['category:stripping'],
            description => <<'_',

Only relevant when stripping using Perl::Stripper.

_
        },
        stripper_log => {
            summary => "Set strip_log=1 (strip log statements) in Perl::Stripper",
            'summary.alt.bool.not' => "Set strip_log=0 (don't strip log statements) in Perl::Stripper",
            schema => ['bool'],
            default => 0,
            tags => ['category:stripping'],
            description => <<'_',

Only relevant when stripping using Perl::Stripper.

_
        },
        # XXX strip_log_levels

    },
};
sub datapack_modules {
    my %args = @_;

    my %module_srcs; # key: mod_pm
    if ($args{module_srcs}) {
        for my $mod (keys %{ $args{module_srcs} }) {
            my $mod_pm = $mod; $mod_pm =~ s!::!/!g; $mod_pm .= ".pm";
            $module_srcs{$mod_pm} = $args{module_srcs}{$mod};
        }
    } else {
        require Module::Path::More;
        for my $mod (@{ $args{module_names} }) {
            my $mod_pm = $mod; $mod_pm =~ s!::!/!g; $mod_pm .= ".pm";
            next if $module_srcs{$mod_pm};
            my $path = Module::Path::More::module_path(
                module => $mod, find_pmc=>0);
            die "Can't find module '$mod_pm'" unless $path;
            $module_srcs{$mod_pm} = do {
                local $/;
                open my($fh), "<", $path or die "Can't open $path: $!";
                ~~<$fh>;
            };
        }
    }

    if ($args{stripper}) {
        require Perl::Stripper;
        my $stripper = Perl::Stripper->new(
            maintain_linum => $args{stripper_maintain_linum} // 0,
            strip_ws       => $args{stripper_ws} // 1,
            strip_comment  => $args{stripper_comment} // 1,
            strip_pod      => $args{stripper_pod} // 1,
            strip_log      => $args{stripper_log} // 0,
        );
        for my $mod_pm (keys %module_srcs) {
            $module_srcs{$mod_pm} = $stripper->strip($module_srcs{$mod_pm});
        }
    }

    my @res;

    push @res, $args{preamble} if defined $args{preamble};
    push @res, <<'_';
# BEGIN DATAPACK CODE
{
    my $toc;
    my $data_linepos = 1;
    unshift @INC, sub {
        $toc ||= do {

            # calculate the line number of data section
            my $data_pos = tell(DATA);
            seek DATA, 0, 0;
            my $pos = 0;
            while (1) {
                my $line = <DATA>;
                $pos += length($line);
                $data_linepos++;
                last if $pos >= $data_pos;
            }
            seek DATA, $data_pos, 0;

            my $fh = \*DATA;
# INSERT_BLOCK: Data::Section::Seekable::Reader read_dss_toc
            \%toc;
        };
        if ($toc->{$_[1]}) {
            seek DATA, $toc->{$_[1]}[0], 0;
            read DATA, my($content), $toc->{$_[1]}[1];
            my ($order, $lineoffset) = split(';', $toc->{$_[1]}[2]);
            $content = "# line ".($data_linepos + 1 + keys(%$toc) + 1 + $order + $lineoffset)." \"".__FILE__."\"\n" . $content;
            open my $fh, '<', \$content
                or die "DataPacker error loading $_[1] (could be a perl installation issue?)";
            return $fh;
        }
        return;
    };
}
# END DATAPACK CODE
_

    push @res, $args{postamble} if defined $args{postamble};

    require Data::Section::Seekable::Writer;
    my $writer = Data::Section::Seekable::Writer->new(separator => "---\n");
    my $linepos = 0;
    $writer->add_part("00separator" => "", "0;0");
    my $i = 0;
    for my $mod_pm (sort keys %module_srcs) {
        $i++;
        my $content = join(
            "",
            $module_srcs{$mod_pm},
        );
        $writer->separator("=== START OF $mod_pm ===\n");
        $writer->add_part($mod_pm => $content, "$i;$linepos");
        my $lines = 0; $lines++ while $content =~ /^/gm;
        $linepos += $lines;
    }
    push @res, "\n__DATA__\n", $writer;

    if ($args{output}) {
        my $outfile = $args{output};
        if (-f $outfile) {
            return [409, "Won't overwrite existing file '$outfile'"]
                unless $args{overwrite};
        }
        open my($fh), ">", $outfile or die "Can't write to '$outfile': $!";
        print $fh join("", @res);
        return [200, "OK, written to '$outfile'"];
    } else {
        return [200, "OK", join("", @res)];
    }
}

1;
# ABSTRACT:

=head1 SEE ALSO

L<App::FatPack>, L<App::fatten>
