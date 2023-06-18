#!/usr/bin/env raku
use lib './Fast.pm6';
use nqp;

# No standard input/output buffering to prevent unwanted hangs/failures/waits
$*OUT.out-buffer = False;
$*ERR.out-buffer = False;

debug-log("🙂: Starting raku-langserver... Reading/writing stdin/stdout.");

start-listen();

sub start-listen() is export {
  my %request;

  loop {
    my $content-length = get_content_length();

    if $content-length == 0 {
      next;
    }

    # debug-log("length is: " ~ $content-length);

    %request = read_request($content-length);

    unless %request {
      next;
    }

    # debug-log(%request);
    process_request(%request);

  }
}


sub get_content_length {

  my $content-length = 0;
  for $*IN.lines -> $line {

    # we're done here
    last if $line eq '';

    # Parse HTTP-style header
    my ($name, $value) = $line.split(': ');
    if $name eq 'Content-Length' {
      $content-length += $value;
    }
  }

  # If no Content-Length in the header
  return $content-length;
}

sub read_request($content-length) {
  my $json    = $*IN.read($content-length).decode;
  my %request = from-json($json);

  return %request;
}

sub process_request(%request) {
  # TODO throw an exception if a method is called before $initialized = True
  # debug-log(%request);
  given %request<method> {
    when 'initialize' {
      my $result = initialize(%request<params>);
      send-json-response(%request<id>, $result);
    }
    when 'textDocument/didOpen' {
      check-syntax(%request, "open");
    }
    when 'textDocument/didSave' {
      check-syntax(%request, "save");
    }
    when 'textDocument/didChange' {
      check-syntax(%request, "change");
    }
    when 'shutdown' {
      # Client requested to shutdown...
      send-json-response(%request<id>, Any);
    }
    when 'exit' {
      exit 0;
    }
  }
}

sub debug-log($text) is export {
  $*ERR.say($text);
}

sub send-json-response($id, $result) {
  my %response = %(
    jsonrpc => "2.0",
    id       => $id,
    result   => $result,
  );
  my $json-response = to-json(%response, :!pretty);
  my $content-length = $json-response.chars;
  my $response = "Content-Length: $content-length\r\n\r\n" ~ $json-response;
  print($response);
}


sub send-json-request($method, %params) {
  my %request = %(
    jsonrpc  => "2.0",
    'method' => $method,
    params   => %params,
  );
  my $json-request = to-json(%request);
  my $content-length = $json-request.chars;
  my $request = "Content-Length: $content-length\r\n\r\n" ~ $json-request;
  # debug-log($request);
  print($request);
}

sub initialize(%params) {
  %(
    capabilities => {
      # TextDocumentSyncKind.Full
      # Documents are synced by always sending the full content of the document.
      textDocumentSync => 1,

      # Provide outline view support (not)
      documentSymbolProvider => False,

      # Provide hover support (not)
      hoverProvider => False
    }
  )
}

sub check-syntax(%params, $type) {

  my $uri = %params<params><textDocument><uri>;
  my $code;
  if ($type eq "change") {
    $code = %params<textDocument><text> || %params<params><contentChanges>[0]<text>;
  } else {
    my $file;
    if $uri ~~ /file\:\/\/(.+)/ {
      $file = $/[0].Str;
    }
    return unless $file.IO.e;
    $code = $file.IO.slurp;
  }

  my @problems = parse-error($code) || [];


  my %parameters = %(
    uri         => $uri,
    diagnostics => @problems
  );
 
  send-json-request('textDocument/publishDiagnostics', %parameters);


  return;
}

grammar ErrorMessage {
  token TOP { <Error>+ }
  token Error { <Warning> || <Missing-libs> || <Undeclared-name> || <Missing-generics> }

  rule Undeclared-name { <ErrorInit> Undeclared <Undeclared-type>s?\:\r?\n\s+<Name> used at lines? <Linenum>\.? <Message> .* }
  rule Missing-generics{ <ErrorInit> <Error-type> <-[\:]>+\:<Linenum> \s* "------>" <Message>? }
  rule Missing-libs { <ErrorInit> Could not find <Name> in\:<-[\:]>+\:<Linenum> }
  token Warning { "Potential difficulties:" \n <Error-type> <-[\:]>+\:<Linenum> \s* "------>" <Message>? }

  token Error-type { \N* }
  token Undeclared-type { routine || name }
  token Name { <-[\'\s]>+ }
  token Linenum { \d+ }
  token Message { .* }
  token ErrorInit { '[31m===[0mSORRY![31m===[0m' \N+ }
}

class ErrorMessage-actions {
  method TOP ($/) {
    make $<Error>.map( -> $e {
      my $line-number;
      my $message;
      my $severity = 1;

      given $e {
        when $e<Missing-libs> {
          $line-number = $e<Missing-libs><Linenum>.Int;
          $message = qq[Could not find Library $e<Missing-libs><Name>];
        }
        when $e<Missing-generics> {
          $line-number = $e<Missing-generics><Linenum>.Int;
          $message = qq[$e<Missing-generics><Error-type>\n{$e<Missing-generics><Message>.trim.subst(/\x1b\[\d+m/, '', :g)}];
        }
        when $e<Undeclared-name> {
          $line-number = $e<Undeclared-name><Linenum>.Int;
          $message = qq[Undelcared $e<Undeclared-name><Undeclared-type> $e<Undeclared-name><Name>. {$e<Undeclared-name><Message>.trim.subst(/\x1b\[\d+m/, '', :g)}];
        }
        when $e<Warning> {
          $line-number = $e<Warning><Linenum>.Int;
          $message = qq[{$e<Warning><Error-type>.trim}\n{$e<Warning><Message>.trim.subst(/\x1b\[\d+m/, '', :g)}];
          $severity = 3;
        }
      }

      my Bool $vim = True;
      $line-number-- if $vim;

      ({
        range => {
          start => {
            line      => $line-number,
            character => 0
          },
          end => {
            line      => $line-number + 1,
            character => 0
          },
        },
        severity => $severity,
        source   => 'raku -c',
        message  => $message
      })
    })
  }
}

sub extract-info($error) {
    my $line-number;
    my $severity = 1;
    my $message = "";

    given $error.WHO {
      when "X::Syntax::Malformed" {
        $line-number = $error.line;
        $message = $error.message;
      }
      when "X::Undeclared::Symbols" {
        if $error.unk_routines {
          $line-number = $error.unk_routines.values.min[0];
        } else {
          $line-number = $error.unk_types.values.min[0];
        }
        $message = $error.message;
      } 
      when "X::Comp::Group" {
        if $error.panic.line < Inf {
          $line-number = $error.panic.line;
        } else {
          $line-number = $error.panic.unk_routines.values.min[0];
        }
        $message = $error.message;
      } 
      when "X::AdHoc" {
        $line-number = 0;
        $message = $error.payload ~ "\n" ~ $error.backtrace.Str;
      }
      default {
        $line-number = $error.line;
        $message = $error.message;
      }
    }

    return { line-number => $line-number, severity => $severity, message => $message };
}

sub parse-error($code) is export {

  my $*LINEPOSCACHE;
  my $problems;

  my $compiler := nqp::getcomp('Raku') // nqp::getcomp('perl6');
  my $g := nqp::findmethod(
    $compiler,'parsegrammar'
  )($compiler);

  #$g.HOW.trace-on($g);

  my $a := nqp::findmethod(
    $compiler,'parseactions'
  )($compiler);

  try {
    $g.parse( $code, :p( 0 ), :actions( $a ));
  }

  if ($!) {
    my %info = extract-info($!);
    # https://docs.raku.org/type-exception.html
    # https://github.com/rakudo/rakudo/blob/ca7bc91e71afe9373b57cd629215f843e8026df1/src/core.c/Exception.pm6

    $problems = ({
      range => {
        start => {
          line      => %info<line-number> - 1,
          character => 0
        },
        end => {
          line      => %info<line-number> - 1,
          character => 99
        },
      },
      severity => %info<severity>,
      source   => 'Raku',
      message  => %info<message>
    });
  }
  # say debug-log(@problems);
  return $problems;
}
