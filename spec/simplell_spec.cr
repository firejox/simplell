require "./spec_helper"

include Simplell::ParserTool

private module TestGrammar
  new_parser(Parser) do
    new_top_symbol(E) do
      add_rule(t: T, e1: E1) do
        true
      end
    end

    new_symbol(E1) do
      add_rule(plus: '+', t: T, e1: E1) do
        true
      end

      add_rule(e: Eplison) do
        true
      end
    end

    new_symbol(T) do
      add_rule(f: F, t1: T1) do
        true
      end
    end

    new_symbol(T1) do
      add_rule(star: '*', f: F, t1: T1) do
        true
      end

      add_rule(e: Eplison) do
        true
      end
    end

    new_symbol(F) do
      add_rule(lpar: '(', e: E, rpar: ')') do
        true
      end

      add_rule(a: 'i', b: 'd') do
        true
      end
    end
  end

  class Lexer
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
end

describe Simplell do
  it "works" do
    TestGrammar::Parser.parse(TestGrammar::Lexer.new("id + id")).should be_true
  end
end
