use strict;
use warnings;
use Test::More;
use HTML::Blitz ();

my $blitz = HTML::Blitz->new(
    [ '.aa',   [ replace_inner_text => 'AA' ] ],
    [ '.b',    [ replace_inner_var  => 'b' ] ],
    [ '.aaaa', [ replace_inner_text => 'AAAA' ] ],
);

my $template = <<'_EOT_';
<p>x</p>
<p class="aa">x</p>
<p class="b">x</p>
<p class="aaaa">x</p>
<p class="aa b">x</p>
<p class="aa aaaa">x</p>
<p class="b aaaa">x</p>
<p class="aa b aaaa">x</p>
_EOT_

my $result = $blitz->apply_to_html('(test)', $template)->process({ b => 'B' });

is $result, <<'_EOT_';
<p>x</p>
<p class=aa>AA</p>
<p class=b>B</p>
<p class=aaaa>AAAA</p>
<p class="aa b">AA</p>
<p class="aa aaaa">AA</p>
<p class="b aaaa">AAAA</p>
<p class="aa b aaaa">AA</p>
_EOT_

done_testing;
