# simplell [![Build Status](https://travis-ci.org/firejox/simplell.svg?branch=master)](https://travis-ci.org/firejox/simplell)

Simple LL(1) parser generator

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     simplell:
       github: firejox/simplell
   ```

2. Run `shards install`

## Usage

```crystal
require "simplell"

include Simplell::ParserTool

new_parser(MyParser) do
  new_top_symbol(E) do
    add_rule(t: T, e1: E1) do
    end
  end

  new_symbol(E1) do
    add_rule(plus: '+', t: T, e1: E1) do
    end

    add_rule(e: Eplison) do
    end
  end

  new_symbol(T) do
    add_rule(f: F, t1: T1) do
    end
  end

  new_symbol(T1) do
    add_rule(star: '*', f: F, t1: T1) do
    end

    add_rule(e: Eplison) do
    end
  end

  new_symbol(F) do
    add_rule(lpar: '(', e: E, rpar: ')') do
    end

    add_rule(a: 'i', b: 'd') do
    end
  end
end


class MyLexer
  @reader : Char::Reader

  def initialize(str : String)
    @reader = Char::Reader.new str
    ignore_spaces
  end

  def peek
    if (ch = @reader.current_char) != '\0'
      ch
    else
      Simplell::EndMarker.new
    end
  end

  def shift
    if @reader.has_next?
      @reader.next_char
      ignore_spaces
    end
  end

  def ignore_spaces
    while @reader.current_char == ' '
      @reader.next_char
    end
  end
end

MyParser.parse(MyLexer.new("id + id"))
```

## Contributing

1. Fork it (<https://github.com/firejox/simplell/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Firejox](https://github.com/firejox) - creator and maintainer
