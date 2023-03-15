use strict;
use warnings;
use Test::More;
use HTML::Blitz ();

{
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
}

{
    my $blitz = HTML::Blitz->new(
        [ '.f', [ transform_inner_sub => sub { "f-$_[0]" } ],
                [ transform_inner_var => 'f' ] ],
        [ '.g', [ transform_inner_sub => sub { "$_[0]-g" } ],
                [ transform_inner_var => 'g' ] ],
    );

    my $template = <<'_EOT_';
<p>x</p>
<p class="f">case 1</p>
<p class="g">case 2</p>
<p class="f g">case 3</p>
_EOT_

    my $result = $blitz->apply_to_html('(test)', $template)->process({
        f => sub { uc $_[0] },
        g => sub { "<<$_[0]>>" },
    });

    is $result, <<'_EOT_';
<p>x</p>
<p class=f>F-CASE 1</p>
<p class=g>&lt;&lt;case 2-g>></p>
<p class="f g">&lt;&lt;F-CASE 3-G>></p>
_EOT_
}

done_testing;
