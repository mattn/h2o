#! /usr/bin/perl

# Copyright (c) 2014 DeNA Co., Ltd.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.

use strict;
use warnings;
use List::Util qw(max);
use List::MoreUtils qw(uniq);
use Text::MicroTemplate qw(render_mt);

use constant LICENSE => << 'EOT';
/*
 * Copyright (c) 2014 DeNA Co., Ltd.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to
 * deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 * sell copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 * IN THE SOFTWARE.
 */
EOT

my %tokens;
my @hpack;

while (my $line = <DATA>) {
    chomp $line;
    my ($hpack_index, $name, $value) = split /\s+/, $line, 3;
    next unless $name ne '';
    $tokens{$name} = $hpack_index
        unless defined $tokens{$name};
    if ($hpack_index != -1) {
        $hpack[$hpack_index - 1] = [ $name, $value ];
    }
}

my @tokens = map { [ $_, $tokens{$_} ] } uniq sort keys %tokens;

# generate token.h
open my $fh, '>', 'include/h2o/token.h'
    or die "failed to open include/h2o/token.h:$!";
print $fh render_mt(<< 'EOT', \@tokens, LICENSE)->as_string;
? my ($tokens, $license) = @_;
<?= $license ?>
/* DO NOT EDIT! generated by tokens.pl */
#ifndef h2o__token_h
#define h2o__token_h

? for my $i (0..$#$tokens) {
#define <?= normalize_name($tokens->[$i][0]) ?> (h2o__tokens + <?= $i ?>)
? }

#endif
EOT
close $fh;

# generate token_table.h
open $fh, '>', 'src/token_table.h'
    or die "failed to open src/token_table.h:$!";
print $fh render_mt(<< 'EOT', \@tokens, LICENSE)->as_string;
? my ($tokens, $license) = @_;
<?= $license ?>
/* DO NOT EDIT! generated by tokens.pl */
h2o_token_t h2o__tokens[] = {
? for my $i (0..$#$tokens) {
    { { H2O_STRLIT("<?= $tokens->[$i][0] ?>") }, <?= $tokens->[$i][1] ?> }<?= $i == $#$tokens ? '' : ',' ?>
? }
};
size_t h2o__num_tokens = <?= scalar @$tokens ?>;

const h2o_token_t *h2o_lookup_token(const char *name, size_t len)
{
    switch (len) {
? for my $len (uniq sort { $a <=> $b } map { length $_->[0] } @$tokens) {
    case <?= $len ?>:
        switch (h2o_tolower(name[<?= $len - 1 ?>])) {
?  my @tokens_of_len = grep { length($_->[0]) == $len } @$tokens;
?  for my $end (uniq sort map { substr($_->[0], length($_->[0]) - 1) } @tokens_of_len) {
        case '<?= $end ?>':
?   my @tokens_of_end = grep { substr($_->[0], length($_->[0]) - 1) eq $end } @tokens_of_len;
?   for my $token (@tokens_of_end) {
            if (h2o_lcstris_core(name, "<?= substr($token->[0], 0, length($token->[0]) - 1) ?>", <?= length($token->[0]) - 1 ?>))
                return <?= normalize_name($token->[0]) ?>;
?   }
            break;
?  }
        }
        break;
? }
    }

    return NULL;
}
EOT
close $fh;

# generate hpack_static_table.h
open $fh, '>', 'src/http2/hpack_static_table.h'
    or die "failed to open src/hpack_static_table.h:$!";
print $fh render_mt(<< 'EOT', \@hpack, LICENSE)->as_string;
? my ($entries, $license) = @_;
<?= $license ?>
/* automatically generated by tokens.pl */

static const struct st_h2o_hpack_static_table_entry_t h2o_hpack_static_table[<?= scalar @$entries ?>] = {
? for my $i (0..$#$entries) {
    { <?= normalize_name($entries->[$i][0]) ?>, { H2O_STRLIT("<?= $entries->[$i][1] || "" ?>") } }<?= $i == $#$entries ? "" : "," ?>
? }
};
EOT
close $fh;

sub normalize_name {
    my $n = shift;
    $n =~ s/^://;
    $n =~ s/-/_/g;
    $n =~ tr/a-z/A-Z/;
    "H2O_TOKEN_$n";
}

__DATA__
1 :authority
2 :method GET
3 :method POST
4 :path /
5 :path /index.html
6 :scheme http
7 :scheme https
8 :status 200
9 :status 204
10 :status 206
11 :status 304
12 :status 400
13 :status 404
14 :status 500
15 accept-charset
16 accept-encoding gzip, deflate
17 accept-language
18 accept-ranges
19 accept
20 access-control-allow-origin
21 age
22 allow
23 authorization
24 cache-control
25 content-disposition
26 content-encoding
27 content-language
28 content-length
29 content-location
30 content-range
31 content-type
32 cookie
33 date
34 etag
35 expect
36 expires
37 from
38 host
39 if-match
40 if-modified-since
41 if-none-match
42 if-range
43 if-unmodified-since
44 last-modified
45 link
46 location
47 max-forwards
48 proxy-authenticate
49 proxy-authorization
50 range
51 referer
52 refresh
53 retry-after
54 server
55 set-cookie
56 strict-transport-security
57 transfer-encoding
58 user-agent
59 vary
60 via
61 www-authenticate
0 connection
0 x-reproxy-url
0 upgrade
0 http2-settings
