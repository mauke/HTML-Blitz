[![Coverage Status](https://coveralls.io/repos/github/mauke/HTML-Blitz/badge.svg?branch=main)](https://coveralls.io/github/mauke/HTML-Blitz?branch=main)

# NAME

HTML::Blitz - high-performance, selector-based, content-aware HTML template engine

# SYNOPSIS

```perl
use HTML::Blitz ();
my $blitz = HTML::Blitz->new;

$blitz->add_rules(@rules);

my $template = $blitz->apply_to_file("template.html");
my $html = $template->process($variables);

my $fn = $template->compile_to_sub;
my $html = $fn->($variables);
```

# DESCRIPTION

HTML::Blitz is a high-performance, CSS-selector-based, content-aware template
engine for HTML5. Let's unpack that:

- You want to generate web pages. Those are written in HTML5.
- Your HTML documents are mostly static in nature, but some parts need to be
filled in dynamically (often with data obtained from a database query). This is
where a template engine shines.

    (On the other hand, if you prefer to generate your HTML completely dynamically
    with ad-hoc code, but you still want to be safe from HTML injection and XSS
    vulnerabilities, have a look at [HTML::Blitz::Builder](https://metacpan.org/pod/HTML%3A%3ABlitz%3A%3ABuilder).)

- Most template systems are content agnostic: They can be used for pretty much
any format or language as long as it is textual.

    HTML::Blitz is different. It is restricted to HTML, but that also means it
    understands more about the documents it processes, which eliminates certain
    classes of bugs. (For example, HTML::Blitz will never produce mismatched tags
    or forget to properly encode HTML entities.)

- The format for HTML::Blitz template files is plain HTML. Instead of embedding
special template directives in the source document (like with most other
template systems), you write a separate piece of Perl code that instructs
HTML::Blitz to fill in or repeat elements of the source document. Those
elements are targeted with CSS selectors.
- Having written the HTML document template and the corresponding processing
rules (consisting of CSS selectors and actions to be applied to matching
elements), you then compile them together into an [HTML::Blitz::Template](https://metacpan.org/pod/HTML%3A%3ABlitz%3A%3ATemplate)
object. This object provides functions that take a set of input values, insert
them into the document template, and return the finished HTML page.

    This latter step is quite fast. See ["PERFORMANCE"](#performance) for details.

## General flow

In a typical web application, HTML::Blitz is intended to be used in the
following way ("compile on startup"):

1. When the application starts up, do the following steps:

    For each template, create an HTML::Blitz object by calling ["new"](#new).

2. Tell the object what rules to apply, either by passing them to ["new"](#new), or by
calling ["add\_rules"](#add_rules) afterwards (or both). This doesn't do much yet; it just
accumulates rules inside the object.
3. Apply the rules to the source document by calling ["apply\_to\_file"](#apply_to_file) (if the
source document is stored in a file) or ["apply\_to\_html"](#apply_to_html) (if you have the
source document in a string). This gives you an [HTML::Blitz::Template](https://metacpan.org/pod/HTML%3A%3ABlitz%3A%3ATemplate)
object.
4. Turn the [HTML::Blitz::Template](https://metacpan.org/pod/HTML%3A%3ABlitz%3A%3ATemplate) object into a function by calling
["compile\_to\_sub" in HTML::Blitz::Template](https://metacpan.org/pod/HTML%3A%3ABlitz%3A%3ATemplate#compile_to_sub). Stash the function away somewhere.

    (The previous steps are meant to be performed once, when the application starts
    up and initializes.)

5. When a request comes in, retrieve the corresponding template function from
where you stashed it in step 4, then call it with the set of variables you want
to use to populate the template document. The result is the finished HTML page.

Alternatively, if your application is not persistent (e.g. because it exits
after processing each request, like a CGI script) or if you just don't want to
spend time recompiling each template on startup, you can use a different model
("precompiled") as follows:

1. In a separate script, run steps 1 to 3 from the list above in advance.
2. Serialize each template to a string by calling
["compile\_to\_string" in HTML::Blitz::Template](https://metacpan.org/pod/HTML%3A%3ABlitz%3A%3ATemplate#compile_to_string) and store it where you can load it
back later, e.g. in a database or on disk. In the latter case, you can simply
call ["compile\_to\_file" in HTML::Blitz::Template](https://metacpan.org/pod/HTML%3A%3ABlitz%3A%3ATemplate#compile_to_file) directly.
3. Take care to recompile your templates as needed by rerunning steps 1 and 2 each
time the source documents or processing rules change.
4. In your application, load your template functions by `eval`'ing the code
stored in step 2. In the case of files, you can simply use ["do EXPR" in perlfunc](https://perldoc.perl.org/perlfunc#do-EXPR).
The return value will be a subroutine reference.
5. Call your template functions as described in step 5 above.

## Processing model

Conceptually, HTML::Blitz operates in two phases: First all selectors are
tested against the source document and their matches recorded. Then, in the
second phase, all matching actions are applied.

Consider the following document fragment:

```html
<div class="foo"> ... </div>
```

And these rules:

```perl
[ 'div' => ['remove_all_attributes'] ],
[ '.foo' => ['replace_inner_text', 'Hello!'] ],
```

The second rule matches against the `class` attribute, but the first rule
removes all attributes. However, it doesn't matter in what order you define
these rules: Both selectors are matched first, and then both actions are
applied together. The attribute removal does not prevent the second rule from
matching. The result will always come out as:

```html
<div>Hello!</div>
```

In cases where multiple actions apply to the same element, all actions are run,
but their order is unspecified. Consider the following document fragment:

```html
<div class="foo"> ... </div>
```

And these rules:

```perl
[ 'div' => ['replace_inner_text', 'A'], ['replace_inner_text', 'B'] ],
[ '.foo' => ['replace_inner_text', 'B'] ],
```

All three actions will run and replace the contents of the `div` element, but
since their order is unspecified, you may end up with any of the following
three results (depending on which action runs last):

```html
<div class="foo">A</div>
```

or

```html
<div class="foo">B</div>
```

or

```html
<div class="foo">C</div>
```

> **Implementation details** (results not guaranteed, your mileage may vary, void
> where prohibited, not financial advice): The current implementation tries to
> maximize an internal metric called "unhelpfulness". Consider the following
> document fragment:
>
> ```html
> <img class="profile" src="dummy.jpg">
> ```
>
> And these actions:
>
> ```perl
> ['remove_all_attributes'],                                          #1
> ['set_attribute_text', src => 'kitten.jpg'],                        #2
> ['set_attribute_text', alt => "Photo of a sleeping kitten"],        #3
> ['transform_attribute_sub', src => sub { "/media/images/$_[0]" }],  #4
> ```
>
> Clearly the most sensible way to arrange these actions is from #1 to #4; first
> removing all existing attributes, giving `<img>`, then gradually setting
> new attributes, giving `<img src="kitten.jpg" alt="Photo of a sleeping kitten">`,
> and finally transforming them. This would result in:
>
> ```html
> <img src="/media/images/kitten.jpg" alt="Photo of a sleeping kitten">
> ```
>
> However, that's too helpful.
>
> In order to maximize unhelpfulness, you would apply these actions from #4 back
> to #1; first transforming the `src` attribute, giving
> `<img class="profile" src="/media/images/dummy.jpg">`, then
> adding/overwriting other attributes, giving
> `<img class="profile" src="kitten.jpg" alt="Photo of a sleeping kitten">`,
> and finally removing all attributes. This would result in:
>
> ```html
> <img>
> ```
>
> And that's what HTML::Blitz actually does.

# METHODS

## new

```perl
my $blitz = HTML::Blitz->new;
my $blitz = HTML::Blitz->new(\%options);
my $blitz = HTML::Blitz->new(@rules);
my $blitz = HTML::Blitz->new(\%options, @rules);
```

Creates a new `HTML::Blitz` object.

You can optionally specify initial options by passing a hash reference as the
first argument. The following keys are supported:

- keep\_doctype

    Default: _true_

    By default, `<!DOCTYPE html>` declarations in template files are retained.
    If you set this option to a false value, they are removed instead.

- keep\_comments\_re

    Default: `qr/\A/`

    By default, HTML comments in template files are retained. This option accepts a
    regex object (as created by [`qr//`](https://perldoc.perl.org/perlfunc#qr-STRING)), which is matched
    against the contents of all HTML comments. Only those that match the regex are
    retained; all others are removed.

    For example, to remove all comments except for copyright notices, you could use
    the following:

    ```perl
    HTML::Blitz->new({
        keep_comments_re => qr/ \(c\) | \b copyright \b | \N{COPYRIGHT SIGN} /xi,
    })
    ```

    If you want to invert this functionality, e.g. to remove comments containing
    `DELETEME` and keep everything else, use negative look-ahead:

    ```perl
    HTML::Blitz->new({
        keep_comments_re => qr/\A(?!.*DELETEME)/s,
    })
    ```

- dummy\_marker\_re

    Default: `qr/\A(?!)/`

    Sometimes you might have dummy content or filler text in your templates that is
    intended to be replaced by your processing rules (like "Lorem ipsum" or user
    details for "Firstname Lastname"). To make sure all such instances are actually
    found and replaced by your processing rules, come up with a distinctive piece
    of marker text (e.g. _XXX_), include it in all of your dummy content, and pass
    a regex object (as created by [`qr//`](https://perldoc.perl.org/perlfunc#qr-STRING)) that detects
    it. For example:

    ```perl
    HTML::Blitz->new({
        dummy_marker_re => qr/\bXXX\b/,
    })
    ```

    If any of the attribute values or plain text parts of your source template
    match this regex, template processing will stop and an exception will be
    thrown.

    Note that this only applies to text from the template; strings that are
    substituted in by your processing rules are not checked.

    The default behavior is to not detect/reject dummy content.

All other arguments are interpreted as processing rules:

```perl
my $blitz = HTML::Blitz->new(@rules);
```

is just a shorter way to write

```perl
my $blitz = HTML::Blitz->new;
$blitz->add_rules(@rules);
```

See ["add\_rules"](#add_rules).

## set\_keep\_doctype

```perl
$blitz->set_keep_doctype(1);
$blitz->set_keep_doctype(0);
```

Turns the ["keep\_doctype"](#keep_doctype) option on/off. See the description of ["new"](#new) for
details.

## set\_keep\_comments\_re

```perl
$blitz->set_keep_comments_re( qr/copyright/i );
```

Sets the ["keep\_comments\_re"](#keep_comments_re) option. See the description of ["new"](#new) for
details.

## set\_dummy\_marker\_re

```perl
$blitz->set_dummy_marker_re( qr/\bXXX\b/ );
```

Sets the ["dummy\_marker\_re"](#dummy_marker_re) option. See the description of ["new"](#new) for
details.

## add\_rules

```perl
$blitz->add_rules(
    [ 'a.info, a.next' =>
        [ set_attribute_text => 'href', 'https://example.com/' ],
        [ replace_inner_text => "click here" ],
    ],
    [ '#list-container' =>
        [ repeat_inner => 'list',
            [ '.name'  => [ replace_inner_var => 'name' ] ],
            [ '.group' => [ replace_inner_var => 'group' ] ],
            [ 'hr'     => ['separator'] ],
        ],
    ],
);
```

The `add_rules` method adds processing rules to the `HTML::Blitz` object. It
accepts any number of rules (even 0, but calling it without arguments is a
no-op).

A _rule_ is an array reference whose first element is a selector and whose
remaining elements are processing actions. The actions will be applied to all
HTML elements in the template document that match the selector.

A _selector_ is a CSS selector group in the form of a string.

An _action_ is an array reference whose first element is a string that
specifies the type of the action; the remaining elements are arguments.
Different types of actions take different kinds of arguments.

A selector group is a comma-separated list of one or more selectors. It matches
any element matched by any of the selectors in the list.

A selector is one or more simple selector sequences separated by a combinator.

The available combinators are whitespace, `>`, `~`, and `+`. For all
simple selector sequences _S1_, _S2_:

- The descendant combinator `S1 S2` matches any element _S2_ that has an
ancestor matching _S1_.
- The child combinator `S1 > S2` matches any element _S2_ that has an
immediate parent element matching _S1_.
- The sibling combinator `S1 ~ S2` matches any element _S2_ that has a
preceding sibling element matching _S1_.
- The adjacent sibling combinator `S1 + S2` matches any element _S2_ that has
an immediately preceding sibling element matching _S1_.

**Limitation:** In the current implementation, the number of adjacent
non-descendant combinators is limited by the number of bits that perl uses for
integers. That is, you cannot use more than 32 (if your perl uses 32-bit
integers) or 64 (if your perl uses 64-bit integers) simple selector sequences
in a row if they are all joined using `>`, `~`, or `+`. (No limit is
placed on the number of simple selectors in a sequence, nor on simple selector
sequences joined using the descendant combinator (whitespace).)

A simple selector sequence is a sequence of one or more simple selectors
separated by nothing (not even whitespace). If a universal or type selector is
present, it must come first in the sequence. A sequence matches any element
that is matched by all of the simple selectors in the sequence.

A simple selector is one of the following:

- universal selector

    The universal selector `*` matches all elements. It is generally redundant and
    can be omitted unless it is the only component of a selector sequence.
    (Selector sequences cannot be empty.)

- type selector

    A type selector consists of a name. It matches all elements of that name. For
    example, a selector of `form` matches all form elements, `p` matches all
    paragraph elements, etc.

- attribute presence selector

    A selector of the form `[FOO]` (where `FOO` is a CSS identifier) matches all
    elements that have a `FOO` attribute.

- attribute value selector

    A selector of the form `[FOO=BAR]` (where `BAR` is a CSS identifier or a CSS
    string in single or double quotes) matches all elements that have a `FOO`
    attribute whose value is exactly `BAR`.

- attribute prefix selector

    A selector of the form `[FOO^=BAR]` (where `BAR` is a CSS identifier or a CSS
    string in single or double quotes) matches all elements that have a `FOO`
    attribute whose value starts with `BAR`. However, if `BAR` is the empty
    string (i.e. the selector looks like `[FOO^=""]` or `FOO^='']`), then it
    matches nothing.

- attribute suffix selector

    A selector of the form `[FOO$=BAR]` (where `BAR` is a CSS identifier or a CSS
    string in single or double quotes) matches all elements that have a `FOO`
    attribute whose value ends with `BAR`. However, if `BAR` is the empty
    string (i.e. the selector looks like `[FOO$=""]` or `FOO$='']`), then it
    matches nothing.

- attribute infix selector

    A selector of the form `[FOO*=BAR]` (where `BAR` is a CSS identifier or a CSS
    string in single or double quotes) matches all elements that have a `FOO`
    attribute whose value contains `BAR` as a substring. However, if `BAR` is the
    empty string (i.e. the selector looks like `[FOO*=""]` or `FOO*='']`), then
    it matches nothing.

- attribute word selector

    A selector of the form `[FOO~=BAR]` (where `BAR` is a CSS identifier or a CSS
    string in single or double quotes) matches all elements that have a `FOO`
    attribute whose value is a list of whitespace-separated words, one of which is
    exactly `BAR`.

- attribute language prefix selector

    A selector of the form `[FOO|=BAR]` (where `BAR` is a CSS identifier or a CSS
    string in single or double quotes) matches all elements that have a `FOO`
    attribute whose value is either exactly `BAR` or starts with `BAR` followed
    by a `-` (minus) character. For example, `[lang|=en]` would match an
    attribute of the form `lang="en"`, but also `lang="en-us"`, `lang="en-uk"`,
    `lang="en-fr"`, etc.

- class selector

    A selector of the form `.FOO` (where `FOO` is a CSS identifier) matches all
    elements whose `class` attribute contains a list of whitespace-separated
    words, one of which is exactly `FOO`. It is equivalent to `[class~=FOO]`.

- identity selector

    A selector of the form `#FOO` (where `FOO` is a CSS name) matches all
    elements whose `id` attribute is exactly `FOO`. It is equivalent to
    `[id=FOO]`.

- _n_th child selector

    A selector of the form `:nth-child(An+B)` or `:nth-child(An-B)` (where `A`
    and `B` are integers) matches all elements that are the _An+B_th (or
    _An-B_th, respectively) child of their parent element, for any non-negative
    integer _n_. For the purposes of this selector, counting starts at 1.

    The full syntax is a bit more complicated: `A` can be negative; if `A` is 1,
    it can be omitted (i.e. `1n` can be shortened to just `n`); if `A` is 0, the
    whole `An` part can be omitted; if `B` is 0, the `+B` (or `-B`) part can be
    omitted unless the `An` part is also gone; `n` can also be written `N`.

    In short, all of these are valid arguments to `:nth-child`:

    ```css
    3n+1
    3n-2
    -4n+7
    2n
    9
    n-2
    1n-0
    ```

    In addition, the special keywords `odd` and `even` are also accepted.
    `:nth-child(odd)` is equivalent to `:nth-child(2n+1)` and `:nth-child(even)`
    is equivalent to `:nth-child(2n)`.

- _n_th child of type selector

    A selector of the form `:nth-of-type(An+B)` or `:nth-of-type(An-B)` (where
    `A` and `B` are integers) matches all elements that are the _An+B_th (or
    _An-B_th, respectively) child of their parent element, only counting elements
    of the same type, for any non-negative integer _n_. Counting starts at 1.

    It accepts the same argument syntax as the ["_n_th child selector"](#nth-child-selector), which
    see for details.

    For example, `span:nth-of-type(3)` matches every `span` element whose list of
    preceding sibling contains exactly two elements of type `span`.

- first child selector

    A selector of the form `:first-child` matches all elements that have no
    preceding sibling elements. It is equivalent to `:nth-child(1)`.

- first child of type selector

    A selector of the form `:first-of-type` matches all elements that have no
    preceding sibling elements of the same type. It is equivalent to
    `:nth-of-type(1)`.

- negated selector

    A selector of the form `:not(FOO)` (where `FOO` is any simple selector
    excluding the negated selector itself) matches all elements that are not
    matched by `FOO`.

    For example, `img:not([alt])` matches all `img` elements without an `alt`
    attribute, and `:not(*)` matches nothing.

Other selectors or pseudo-classes are not currently implemented.

In the following section, a _variable name_ refers to a string that starts
with a letter or `_`) (underscore), followed by 0 or more letters, `_`,
digits, `.`, or `-`. Template variables identify sections that are filled in
later when the template is expanded (at runtime, so to speak).

The following types of actions are available:

- `['remove']`

    Removes the matched element. Equivalent to `['replace_outer_text', '']`.

- `['remove_inner']`

    Removes the contents of the matched element, leaving it empty. Equivalent to `['replace_inner_text', '']`.

- `['remove_if', VAR]`

    Removes the matched element if _VAR_ (a runtime variable) contains a true value.

- `['replace_inner_text', STR]`

    Replaces the contents of the matched element by the fixed string _STR_.

- `['replace_inner_var', VAR]`

    Replaces the contents of the matched element by the value of the runtime
    variable _VAR_, which is interpreted as plain text (and properly HTML
    escaped).

- `['replace_inner_template', TEMPLATE]`

    Replaces the contents of the matched element by _TEMPLATE_, which must be an
    instance of [HTML::Blitz::Template](https://metacpan.org/pod/HTML%3A%3ABlitz%3A%3ATemplate). This action lets you include a
    sub-template as part of an outer template; all variables of the inner template
    become variables of the outer template.

- `['replace_inner_dyn_builder', VAR]`

    Replaces the contents of the matched element by the value of the runtime
    variable _VAR_, which must be an instance of [HTML::Blitz::Builder](https://metacpan.org/pod/HTML%3A%3ABlitz%3A%3ABuilder). This is
    the only way to incorporate dynamic HTML in a template (without interpreting
    the HTML code as text and escaping everything).

- `['replace_outer_text', STR]`

    Replaces the matched element (and all of its contents) by the fixed string _STR_.

- `['replace_outer_var', VAR]`

    Replaces the matched element (and all of its contents) by the value of the
    runtime variable _VAR_, which is interpreted as plain text (and properly HTML
    escaped).

- `['replace_outer_template', TEMPLATE]`

    Replaces the matched element by _TEMPLATE_, which must be an instance of
    [HTML::Blitz::Template](https://metacpan.org/pod/HTML%3A%3ABlitz%3A%3ATemplate). This action lets you include a sub-template as part
    of an outer template; all variables of the inner template become variable of
    the outer template.

- `['replace_outer_dyn_builder', VAR]`

    Replaces the matched element by the value of the runtime variable _VAR_, which
    must be an instance of [HTML::Blitz::Builder](https://metacpan.org/pod/HTML%3A%3ABlitz%3A%3ABuilder). This is the only way to
    incorporate dynamic HTML in a template (without interpreting the HTML code as
    text and escaping everything).

- `['transform_inner_sub', SUB]`

    Collects the text contents of the matched element and all of its descendants in
    a string and passes it to _SUB_, which must be a code reference (or an object
    with an overloaded `&{}` operator). The returned string replaces the previous
    contents of the matched element.

    It is analogous to `elem.textContent = SUB(elem.textContent)` in JavaScript.

- `['transform_inner_var', VAR]`

    Collects the text contents of the matched element and all of its descendants in
    a string and passes it to the runtime variable _VAR_, which must be a code
    reference (or an object with an overloaded `&{}` operator). The returned
    string replaces the previous contents of the matched element.

- `['transform_outer_sub', SUB]`

    Collects the text contents of the matched element and all of its descendants in
    a string and passes it to _SUB_, which must be a code reference (or an object
    with an overloaded `&{}` operator). The returned string replaces the entire
    matched element. (Thus, if _SUB_ returns an empty string, it effectively
    removes the matched element from the document.)

- `['transform_outer_var', VAR]`

    Collects the text contents of the matched element and all of its descendants in
    a string and passes it to the runtime variable _VAR_, which must be a code
    reference (or an object with an overloaded `&{}` operator). The returned
    string replaces the entire matched element.

- `['remove_attribute', ATTR_NAMES]`

    Removes all attributes from the matched element whose names are listed in
    _ATTR\_NAMES_, which must be a list of strings.

- `['remove_all_attributes']`

    Removes all attributes from the matched elements.

- `['replace_all_attributes', ATTR_HASHREF]`

    Removes all attributes from the matched elements and creates new attributes
    based on _ATTR\_HASHREF_, which must be a reference to a hash. Its keys are
    attribute names; its values are array references with two elements: The first
    is either the string `text`, in which case the second element is the attribute
    value as a string, or the string `var`, in which case the second element is a
    variable name and the attribute value is substituted in at runtime.

    For example:

    ```perl
    ['replace_all_attributes', {
        class => [text => 'button cta-1'],
        title => [var => 'btn_title'],
    }]
    ```

    This specifies that the matched element should only have two attributes:
    `class`, with a value of `button cta-1`, and `title`, whose final value will
    come from the runtime variable `btn_title`.

- `['set_attribute_text', ATTR, STR]`

    Creates an attribute named _ATTR_ with a value of _STR_ (a string) in the
    matched element. If an attribute of that name already exists, it is replaced.

    For example:

    ```perl
    ['set_attribute_text', href => 'https://example.com/']
    ```

- `['set_attribute_text', HASHREF]`

    If you want to set multiple attributes at once, you can this form. The keys of
    _HASHREF_ specify the attribute names, and the values specify the attribute
    values.

    For example:

    ```perl
    ['set_attribute_text', { src => $src, alt => $alt, title => $title }]

    # is equivalent to:
    ['set_attribute_text', src => $src],
    ['set_attribute_text', alt => $alt],
    ['set_attribute_text', title => $title],
    ```

- `['set_attribute_var', ATTR, VAR]`

    Creates an attribute named _ATTR_ whose value comes from _VAR_ (a runtime
    variable) in the matched element. If an attribute of that name already exists,
    it is replaced.

    For example:

    ```perl
    ['set_attribute_var', href => 'target_url']
    ```

- `['set_attribute_var', HASHREF]`

    If you want to set multiple attributes at once, you can this form. The keys of
    _HASHREF_ specify the attribute names, and the values specify the names of
    runtime variables from which the attribute values will be taken.

    For example:

    ```perl
    ['set_attribute_var', { src => 'img_src', alt => 'img_alt', title => 'img_title' }]

    # is equivalent to:
    ['set_attribute_var', src => 'img_src'],
    ['set_attribute_var', alt => 'img_alt'],
    ['set_attribute_var', title => 'img_title'],
    ```

- `['set_attributes', ATTR_HASHREF]`

    Works exactly like ["`['replace_all_attributes', ATTR_HASHREF]`"](#replace_all_attributes-attr_hashref), but
    without removing any existing attributes from the matched element.

    For example:

    ```perl
    ['set_attributes', {
        class => [text => 'button cta-1'],
        title => [var => 'btn_title'],
    }]
    ```

    This specifies that the matched element should have two attributes: `class`,
    with a value of `button cta-1`, and `title`, whose final value will come from
    the runtime variable `btn_title`. All other attributes remain unchanged.

- `['transform_attribute_sub', ATTR, SUB]`

    Calls _SUB_, which must be a code reference (or an object with an overloaded
    `&{}` operator), with the value of the attribute named _ATTR_ in the matched
    element. If there is no such attribute, `undef` is passed instead.

    The return value, normally a string, is used as the new value for _ATTR_.
    However, if _SUB_ returns `undef` instead, the attribute is removed entirely.

- `['transform_attribute_var', ATTR, VAR]`

    Calls the runtime variable _VAR_, whose value must be a code reference (or an
    object with an overloaded `&{}` operator), with the value of the attribute
    named _ATTR_ in the matched element. If there is no such attribute, `undef`
    is passed instead.

    The return value, normally a string, is used as the new value for _ATTR_.
    However, if _VAR_ returns `undef` instead, the attribute is removed
    entirely.

- `['add_attribute_word', ATTR, WORDS]`

    Takes the attribute named _ATTR_ from the matched element and treats it as a
    list of whitespace-separated words. Any words from _WORDS_ (a list of strings)
    that are not already present in _ATTR_ will be added to it. If the matched
    element has no _ATTR_ attribute, it is treated as an empty list (thus all
    _WORDS_ are added).

    As a side effect, duplicate words in the original attribute value may be
    removed.

- `['remove_attribute_word', ATTR, WORDS]`

    Takes the attribute named _ATTR_ from the matched element and treats it as a
    list of whitespace-separated words. Any words from _WORDS_ (a list of strings)
    that are present in _ATTR_ will be removed from it. If the resulting value of
    _ATTR_ is empty, the attribute is removed entirely. If the matched element has
    no _ATTR_ attribute to begin with, nothing changes.

    As a side effect, duplicate words in the original attribute value may be
    removed.

- `['add_class', WORDS]`

    Adds the words in _WORDS_ (a list of strings) to the `class` attribute of the
    matched element (unless they are already present there). Equivalent to
    `['add_attribute_word', 'class', WORDS]`.

- `['remove_class', WORDS]`

    Removes the words in _WORDS_ (a list of strings) from the `class` attribute
    of the matched element (if they exist there). Equivalent to
    `['remove_attribute_word', 'class', WORDS]`.

- `['repeat_outer', VAR, ACTIONS?, RULES]`

    Clones the matched element (along with its descendants), once for each element
    of the runtime variable _VAR_, which must contain an array of variable
    environments. Each copy of the matched element has _RULES_ (a list of
    processing rules) applied to it, with variables looked up in the corresponding
    environment taken from _VAR_.

    For example:

    ```perl
    ['repeat_outer', 'things',
        ['.name', ['replace_inner_var', 'name']],
        ['.phone', ['replace_inner_var', 'phone']],
    ]
    ```

    This specifies that the matched element should be repeated once for each
    element of the `things` variable. In each copy, elements with a class of
    `name` should have their contents replaced by the value of the `name`
    variable in the current environment (i.e. the current element of `things`),
    and elements with a class of `phone` should have their contents replaced by
    the value of the `phone` variable in the current loop environment.

    The optional _ACTIONS_ argument, if present, is a reference to a reference to
    an array of actions (yes, that's a reference to a reference). It specifies what
    to do with the matched element itself within the context of the repetition.

    For example, consider the following rule:

    ```perl
    ['.foo' =>
        ['set_attribute_var', title => 'title'],
        ['replace_inner_var', 'content'],
        ['repeat_outer', 'things',
            ...
        ],
    ]
    ```

    This says that elements with a class of `foo` should have their `title`
    attribute set to the value of the string variable `title` and their text
    content replaced by the value of the string variable `content`, and then be
    repeated as directed by the array variable `things`. While this will clone the
    element as many times as there are elements in `things`, the clones will all
    have the same attributes and content.

    On the other hand:

    ```perl
    ['.foo' =>
        ['repeat_outer', 'things',
            \[
                ['set_attribute_var', title => 'title'],
                ['replace_inner_var', 'content'],
            ],
            ...
        ],
    ]
    ```

    With this rule, the `title` attribute and contents of elements with class
    `foo` are taken from the `title` and `content` (sub-)variables inside
    `things`. That is, the variable references `title` and `content` are scoped
    within the loop. This way each copy of the matched element will be different.

    As a special case, if the _ACTIONS_ list only contains one action, the outer
    array can be omitted. That is, instead of a reference to an array reference of
    actions, you can use a reference to an action:

    ```perl
    ['repeat_outer', 'things',
        \[
            ['replace_inner_var', 'content'],
        ],
        ...
    ]

    # can be simplified to:

    ['repeat_outer', 'things',
        \['replace_inner_var', 'content'],
        ...
    ]
    ```

- `['repeat_inner', VAR, RULES]`

    Clones the descendants of the matched element (but not the element itself),
    once for each element of the runtime variable _VAR_, which must contain an
    array of variable environments. Each copy of the descendants has _RULES_
    (a list of processing rules) applied to it, with variables looked up in the
    corresponding environment taken from _VAR_.

    This is very similar to ["`['repeat_outer', VAR, ACTIONS?, RULES]`"](#repeat_outer-var-actions-rules), with
    the following differences:

    1. The matched element acts as a list container and is not repeated.
    2. The _ACTIONS_ argument is not supported.
    3. The _RULES_ list may contain the special ["`['separator']`"](#separator) action, which
    is only allowed in the context of `repeat_inner`.

- `['separator']`

    This action is only available within a ["`['repeat_inner', VAR, RULES]`"](#repeat_inner-var-rules)
    section. It indicates that the matched element is to be removed from the first
    copy of the repeated elements. The results are probably not useful unless the
    matched element is the first child of the parent whose contents are repeated.

    For example, consider the following template code:

    ```html
    <div id="list">
        <hr class="sep">
        <p class="c1">other stuff</p>
        <p class="c2">more stuff</p>
    </div>
    ```

    ... with this set of rules:

    ```perl
    ['#list' =>
        ['repeat_inner', 'things',
            ['.c1' => [...]],
            ['.c2' => [...]],
            ['.sep' => ['separator']],
        ],
    ]
    ```

    Since the `hr` element targeted by the `separator` action occurs at the
    beginning of the section, it acts as a separator: It will not appear in the
    first copy of the section, but every following copy will include it. The
    result will look Like this:

    ```html
    <div id="list">
        
        <p class="c1">...</p>
        <p class="c2">...</p>

        <hr class="sep">
        <p class="c1">...</p>
        <p class="c2">...</p>

        <hr class="sep">
        <p class="c1">...</p>
        <p class="c2">...</p>
        ...
    </div>
    ```

## apply\_to\_html

```perl
my $template = $blitz->apply_to_html($name, $html_code);
```

Applies the processing rules (added in [the constructor](#new) or via
["add\_rules"](#add_rules)) to the specified source document. The first argument is a purely
informational string; it is used to refer to the document in error messages and
the like. The second argument is the HTML code of the source document. The
returned value is an instance of [HTML::Blitz::Template](https://metacpan.org/pod/HTML%3A%3ABlitz%3A%3ATemplate), which see.

There are some restrictions on the HTML code you can pass in. This module does
not implement the full HTML specification; in particular, implicit tags of any
kind are not supported. For example, the following fragment is valid HTML:

```html
<div>
    <p> A
    <p> B
    <p> C
</div>
```

But HTML::Blitz requires you to write this instead:

```html
<div>
    <p> A </p>
    <p> B </p>
    <p> C </p>
</div>
```

This is because implicit closing tags are not supported. In fact, HTML::Blitz
thinks `<p> A <p> B </p> C </p>` is valid HTML code containing a `p` element
nested within another `p`. (It is not; `p` elements don't nest and the second
`</p>` tag should be a syntax error. So don't do that.)

Similarly, a real HTML parser would not create `tr` elements as direct
children of a `table`:

```html
<table
    <tr><td>A</td></tr>
</table>
```

Here an implicit `tbody` element is supposed to be inserted instead:

```html
<table
    <tbody>
        <tr><td>A</td></tr>
    </tbody>
</table>
```

HTML::Blitz does not do that. If you have a rule with a `tbody` selector, it
will only apply to elements explicitly written out in the source document.

In other matters, HTML::Blitz tries to follow HTML parsing rules closely. For
example, it knows about _void elements_ (i.e. elements that have no content),
like `br`, `img`, or `input`. Such elements do not have closing tags:

```html
<!-- this is a syntax error; you cannot "close" a <br> tag  -->
<br></br>
```

It is not generally possible to have a self-closing opening tag:

```html
<!-- syntax error: -->
<div />

<!-- you need to write this instead: -->
<div></div>
```

However, a trailing slash in the opening tag is accepted (and ignored) in void
elements. The following are all equivalent:

```html
<br>
<br/>
<br />
```

Another exception applies to descendants of `math` and `svg` elements, which
follow slightly different rules:

```html
<svg>
    <!-- this is OK; it is parsed as if it were <circle></circle> -->
    <circle/>
</svg>

<!-- this is a syntax error: attempt to self-close a non-void tag outside of svg/math -->
<circle />
```

Similarly, within `math` and `svg` elements you can use `CDATA` blocks with
raw text inside:

```html
<math>
    <!-- OK: equivalent to "a&lt;b&amp;b&lt;c" -->
    <![CDATA[a<b&b<c]]>
</math>

<!-- syntax error: CDATA outside of math/svg -->
<![CDATA[...]]>
```

The (utterly bonkers) special parsing rules for `script` elements are
faithfully implemented:

```html
<!-- OK: -->
<script> /* <!-- */ </script>

<!-- OK: -->
<script> /* <script> <!-- */ </script>

<!-- still OK (script containing raw "</script>" text): -->
<script> /* <!-- <script> </script> --> */ </script>

<!-- still OK: -->
<script> /* <!-- <script> --> */ </script>
```

Attributes may contain whitespace around `=`:

```html
<img src = "kitten.jpg" alt = "photo of a kitten">
```

Attribute values don't need to be quoted if they don't contain whitespace or
"special" characters (one of `` <>="'` ``):

```html
<img src=kitten.jpg alt="photo of a kitten">
<img src = kitten.jpg alt = photo&#32;of&#32;a&#32;kitten>
```

Attributes without values are allowed (and implicitly assigned the empty string as a value):

```html
<input disabled class>
<!-- is equivalent to -->
<input disabled="" class="">
```

## apply\_to\_file

```perl
my $template = $blitz->apply_to_file($filename);
```

A convenience wrapper around ["apply\_to\_html"](#apply_to_html). It reads the contents of
`$filename` (which must be UTF-8 encoded) and calls `apply_to_html($filename, $contents)`.

# EXAMPLES

## Basic variables and lists/repetition

The following is a complete program:

```perl
use strict;
use warnings;
use HTML::Blitz ();

my $template_html = <<'EOF';
<!DOCTYPE html>
<html>
    <head>
        <title>@@@ Hello, people!</title>
    </head>
    <body>
        <h1 id="greeting">@@@ placeholder heading</h1>
        <div id="list">
            <hr class="between">
            <p>
                Name: <span class="name">@@@Bob</span> <br>
                Age: <span class="age">@@@42</span>
            </p>
        </div>
    </body>
</html>
EOF

my $blitz = HTML::Blitz->new({
    # sanity check: die() if any template parts marked '@@@' above are not
    # replaced by processing rules
    dummy_marker_re => qr/\@\@\@/,
});

$blitz->add_rules(
    [ 'html'             => ['set_attribute_text', lang => 'en'] ],
    [ 'title, #greeting' => ['replace_inner_var', 'title'] ],
    [ '#list' =>
        [ 'repeat_inner', 'people',
            [ '.between' => ['separator'] ],
            [ '.name'    => ['replace_inner_var', 'name'] ],
            [ '.age'     => ['replace_inner_var', 'age'] ],
        ],
    ],
);

my $template = $blitz->apply_to_html('(inline document)', $template_html);
my $template_fn = $template->compile_to_sub;

my $data = {
    title  => "Hello, friends, family & other creatures of the sea!",
    people => [
        { name => 'Edward', age => 17 },
        { name => 'Marvin', age => 510_119_077_042 },
        { name => 'Bronze', age => '<redacted>' },
    ],
};

my $html = $template_fn->($data);
print $html;
```

It produces the following output:

```html
<!DOCTYPE html>
<html lang=en>
    <head>
        <title>Hello, friends, family &amp; other creatures of the sea!</title>
    </head>
    <body>
        <h1 id=greeting>Hello, friends, family &amp; other creatures of the sea!</h1>
        <div id=list>
            
            <p>
                Name: <span class=name>Edward</span> <br>
                Age: <span class=age>17</span>
            </p>
        
            <hr class=between>
            <p>
                Name: <span class=name>Marvin</span> <br>
                Age: <span class=age>510119077042</span>
            </p>
        
            <hr class=between>
            <p>
                Name: <span class=name>Bronze</span> <br>
                Age: <span class=age>&lt;redacted></span>
            </p>
        </div>
    </body>
</html>
```

## Hashing inline scripts for Content-Security-Policy (CSP)

If you want to protect against JavaScript code injection (also known as
cross-site scripting or XSS), the first step is to properly escape all user
input that is presented on a web page. HTML::Blitz aims to make this easy (by
making it hard to interpolate raw HTML strings into a template).

A second layer of defense is available in the form of the
[Content-Security-Policy
(CSP)](https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP) HTTP response
header. This header gives a web site fine-grained control over which sources a
browser is allowed to load resources (including script code) from. In
particular, for inline scripts (i.e. those embedded in HTML within
`<script>...</script>` tags) their [SHA-2-based
hashes](https://en.wikipedia.org/wiki/SHA-2) can be added to the
CSP header. Any other scripts (such as those injected by an attacker) will not
be executed by the browser, thwarting any XSS attempts.

HTML::Blitz can be used to automatically extract and hash any script code
embedded in templates. That way you can automatically compute a tailored CSP
value.

Sample HTML template code:

```html
<!doctype html>
<head>
    <style>
        #big-red-button {
            color: white;
            background-color: red;
            font-size: larger;
        }
    </style>
    <script>
        console.log("Hello from the browser console");
    </script>
</head>
<body>
    <h1>CSP Example</h1>
    <button id="big-red-button">Click me!</button>
    <script>
        document.getElementById('big-red-button').onclick = function () {
            alert("Hello!");
        };
    </script>
</body>
```

And the corresponding Perl code:

```perl
use strict;
use warnings;
use HTML::Blitz;
use Digest::SHA qw(sha256_base64);

# Digest::SHA generates unpadded base64, but CSP requires padding on all
# base64 strings. This function adds the required padding.
sub sha256_base64_padded {
    my ($data) = @_;
    my $hash = sha256_base64 $data;
    $hash . '=' x (-length($hash) % 4)
}

# Returns the script code unchanged, but (as a side effect) adds its
# SHA-256 hash to the %seen_script_hashes variable.
my %seen_script_hashes;
my $add_hash = sub {
    my ($script) = @_;
    $seen_script_hashes{sha256_base64_padded $script} = 1;
    $script
};

my $blitz = HTML::Blitz->new(
    # hash the contents of all <script> tags without a src attribute
    [ 'script:not([src])', [ transform_inner_sub => $add_hash ] ],
    # ... other rules ...
);

my $html = $blitz->apply_to_file('scripts.html')->process();

my @hashes = sort keys %seen_script_hashes;
my $csp = "script-src " . (@hashes ? join(' ', map "'sha256-$_'", @hashes) : "'none'");
# Now you can set a response header of
#   Content-Security-Policy: $csp
# (and a response body of $html) and be sure that only scripts from the
# original template file will execute.
```

# RATIONALE

(I.e. why does this module exist?)

Template systems like [Template::Toolkit](https://metacpan.org/pod/Template%3A%3AToolkit) are both powerful and general. In my
opinion, that's a disadvantage: TT is both too powerful and too stupid for its
own good. Since TT embeds its own programming language that can call arbitrary
methods in Perl, it is possible to write "templates" that send their own
database queries, iterate over resultsets, and do pretty much anything they
want, completely bypassing the notional "controller" or "model" in an
application. On the other hand, since TT knows nothing about the document
structure it is generating (to TT it's all just strings being concatenated),
you have to make sure to manually HTML escape every piece of text. Anything you
overlook may end up being used for HTML injection and XSS exploits.

[HTML::Zoom](https://metacpan.org/pod/HTML%3A%3AZoom) offers an intriguing alternative: Templates are plain HTML
without any special template directives or variables at all. Instead, these
static HTML documents are manipulated through structure-aware selectors and
modification actions. Not only does this eliminate the disadvantages listed
above, it also means you can automatically validate your templates to make sure
they're well-formed HTML, which is basically impossible with TT.

There is only one tiny problem: [HTML::Zoom](https://metacpan.org/pod/HTML%3A%3AZoom) is slow. A template page that
seems fine when fed with 10 or 20 variables during development can suddenly
crawl to a near halt when fed with an unexpectedly large dataset (with hundreds
or thousands of entries) in production.

(In fact, I once had reports of a single page in a big web app taking 50-60
seconds to load, which is clearly unacceptable. At first I tried to optimize
the database queries behind it, but without much success. That's when I
realized that >85% of the time was spent in the [HTML::Zoom](https://metacpan.org/pod/HTML%3A%3AZoom) based view, just
slowly churning through the template, and nothing I changed in the code before
that would significantly improve loading times.)

This module was born from an attempt to retain the general concept behind
[HTML::Zoom](https://metacpan.org/pod/HTML%3A%3AZoom) (which I'm a big fan of) while reimplementing every part of the
API and code with a focus on pure execution speed.

# PERFORMANCE

For benchmarking purposes I set up a simple HTML template and filled it with a
medium-sized dataset consisting of 5 "categories" with 40 "products" each (200
in total). Each "product" had a custom image, description, and other bits of
metadata.

To get a performance baseline, I timed a hand-written piece of Perl code
consisting only of string constants, variables, calls to `encode_entities`
(from [HTML::Entities](https://metacpan.org/pod/HTML%3A%3AEntities)), concatenation, and nested loops. Everything was
hard-coded; nothing was modularized or factored out into subroutines.

Against this, I timed a few template systems ([HTML::Blitz](https://metacpan.org/pod/HTML%3A%3ABlitz), [HTML::Zoom](https://metacpan.org/pod/HTML%3A%3AZoom),
[Template::Toolkit](https://metacpan.org/pod/Template%3A%3AToolkit), [HTML::Template](https://metacpan.org/pod/HTML%3A%3ATemplate), [HTML::Template::Pro](https://metacpan.org/pod/HTML%3A%3ATemplate%3A%3APro),
[Mojo::Template](https://metacpan.org/pod/Mojo%3A%3ATemplate), [Text::Xslate](https://metacpan.org/pod/Text%3A%3AXslate)) as well as [HTML::Blitz::Builder](https://metacpan.org/pod/HTML%3A%3ABlitz%3A%3ABuilder), which
is rather the opposite of a template system.

Results:

- [Text::Xslate](https://metacpan.org/pod/Text%3A%3AXslate) v3.5.9

    1375/s (0.0007s per iteration), 380.9%

- [HTML::Blitz](https://metacpan.org/pod/HTML%3A%3ABlitz) 0.06

    678/s (0.0015s per iteration), 187.8%

- [HTML::Template::Pro](https://metacpan.org/pod/HTML%3A%3ATemplate%3A%3APro) 0.9524

    653/s (0.0015s per iteration), 180.9%

- [Mojo::Template](https://metacpan.org/pod/Mojo%3A%3ATemplate) 9.31

    463/s (0.0022s per iteration), 128.3%

- handwritten

    361/s (0.0028s per iteration), 100.0%

- [Template::Toolkit](https://metacpan.org/pod/Template%3A%3AToolkit) 3.101

    38.6/s (0.0259s per iteration), 10.7%

- [HTML::Template](https://metacpan.org/pod/HTML%3A%3ATemplate) 2.97

    33.5/s (0.0299s per iteration), 9.3%

- [HTML::Blitz::Builder](https://metacpan.org/pod/HTML%3A%3ABlitz%3A%3ABuilder) 0.06

    32.9/s (0.0304s per iteration), 9.1%

- [HTML::Zoom](https://metacpan.org/pod/HTML%3A%3AZoom) 0.009009

    1.24/s (0.8065s per iteration), 0.3%

Conclusions:

- [HTML::Zoom](https://metacpan.org/pod/HTML%3A%3AZoom) is slooooooow. Using it in anything but the most simple cases has
a noticeable impact on performance.
- HTML::Blitz is orders of magnitude faster. It can easily outperform
[HTML::Zoom](https://metacpan.org/pod/HTML%3A%3AZoom) by a factor of 200 or 300. A dataset that might take HTML::Blitz
20 milliseconds to zip through would lock up [HTML::Zoom](https://metacpan.org/pod/HTML%3A%3AZoom) for over 5 seconds.
- HTML::Blitz and [Mojo::Template](https://metacpan.org/pod/Mojo%3A%3ATemplate) are faster than hand-written code. This is
probably because the hand-written code appends each line separately to the
output string and escapes each template parameter by calling
[`HTML::Entities::encode_entities`](https://metacpan.org/pod/HTML%3A%3AEntities#encode_entities-string)
– whereas HTML::Blitz and [Mojo::Template](https://metacpan.org/pod/Mojo%3A%3ATemplate) fold all adjacent constant HTML
pieces into one big string in advance and use their own optimized HTML escape
routine.
- HTML::Blitz can, depending on your workload, run faster than
[HTML::Template::Pro](https://metacpan.org/pod/HTML%3A%3ATemplate%3A%3APro), which is written in C for speed.
- In this comparison, the only system that beats HTML::Blitz in terms of raw
speed is the XS version of [Text::Xslate](https://metacpan.org/pod/Text%3A%3AXslate) (by a factor of about 2). The only
downsides are that it requires a C compiler and pulls in an entire object
system as a dependency ([Mouse](https://metacpan.org/pod/Mouse)). (Without a C compiler it will still run, but
the performance of its pure Perl backend is not competitive, reaching only
about two thirds of the speed of [HTML::Blitz::Builder](https://metacpan.org/pod/HTML%3A%3ABlitz%3A%3ABuilder).)

# WHY THE NAME

I'm German, and _Blitz_ is the German word for "lightning" or "flash" (or
"thunderbolt"). Because the main motivation behind this module is performance,
I wanted something that represents speed. Something _lightning-fast_, in fact
(that's _blitzschnell_ in German). I didn't want to use the English name
"Flash" because that name is already taken by the infamous "Flash Player"
browser plugin (even if it is currently dead).

The second reason is also connected to speed: I wanted a template system that
assembles pages as effortlessly and efficiently as copying around blocks of
memory, with minimal additional computation. Something roughly like a
[bit blit](https://en.wikipedia.org/wiki/Bit_blit) ("bit block transfer")
operation. HTML::Blitz "blits" in the sense that it efficiently transfers
blocks of HTML.

The third reason relates to my frustration with [HTML::Zoom](https://metacpan.org/pod/HTML%3A%3AZoom)'s performance.
When I was struggling with [HTML::Zoom](https://metacpan.org/pod/HTML%3A%3AZoom), fruitlessly trying to come up with
ways to optimize or work around its code, I remembered a funny coincidence: It
just so happens that (Professor) Zoom is the name of a supervillain in the
superhero comic books published by DC Comics. He is the archenemy of the Flash
("the fastest man alive"), whose main ability is super-speed. When the Flash
comics were published in Germany in the 1970s and 1980s, his name was
translated as _der Rote Blitz_ ("the Red Flash"). Thus: "Blitz" is the hero
that triumphs over "Zoom" through superior speed. :-)

# AUTHOR

Lukas Mai, `<lmai at web.de>`

# COPYRIGHT & LICENSE

Copyright 2022-2023 Lukas Mai.

This module is free software: you can redistribute it and/or modify it under
the terms of the [GNU General Public License](https://www.gnu.org/licenses/gpl-3.0.html)
as published by the Free Software Foundation, either version 3 of the License,
or (at your option) any later version.

# SEE ALSO

[HTML::Blitz::Template](https://metacpan.org/pod/HTML%3A%3ABlitz%3A%3ATemplate),
[HTML::Blitz::Builder](https://metacpan.org/pod/HTML%3A%3ABlitz%3A%3ABuilder)
