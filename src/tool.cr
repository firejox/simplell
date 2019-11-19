module Simplell::ParserTool
  private macro new_parser(parser_type)
    @[Simplell::ParserAttr({:rule_counter => 0, :eplison => Eplison, :end_marker => Simplell::EndMarker}, {nil => nil})]
    class {{ parser_type }}
      {{ yield }}

      build_ll_parser
    end
  end

  private macro new_top_symbol(symbol_type)
    {% if ann = @type.annotation(Simplell::ParserAttr) %}
      {% if parser = ann.args[0] %}
        {% unless top = parser[:top_symbol] %}
          {% parser[:top_symbol] = symbol_type %}
          @[Simplell::TopSymbolAttr]
          @[Simplell::SymbolAttr(parser: {{ @type }})]
          class {{ symbol_type }}
            {{ yield }}
          end
        {% else %}
          {% raise "Top Symbol has been defined in parser #{@type}." %}
        {% end %}
      {% else %}
        {% raise "Parser #{@type} is with invalid attribute." %}
      {% end %}   
    {% else %}
      {% raise "Top symbol #{symbol_type} is not contained in valid parser." %}
    {% end %}
  end

  private macro new_symbol(symbol_type)
    {% if ann = @type.annotation(Simplell::ParserAttr) %}
      {% if parser = ann.args[0] %}
        {% if top = parser[:top_symbol] %}
          @[Simplell::SymbolAttr(parser: {{ @type }})]
          class {{ symbol_type }}
            {{ yield }}
          end
        {% else %}
          {% raise "Top symbol is undefined." %}
        {% end %}
      {% else %}
        {% raise "Parser #{@type} is with invalid attribute." %}
      {% end %}
    {% else %}
      {% raise "Symbol #{symbol_type} is not contained in valid parser." %}
    {% end %}
  end

  private macro add_rule(**args)
    {% if ann = @type.annotation(Simplell::SymbolAttr) %}
      {% if args.empty? %}
        {% raise "Rule should not be empty." %}
      {% elsif args[:lexer] %}
        {% raise "`lexer` is a special argument. Don't declare with this name." %}
      {% else %}
        {%
          parser_type = ann[:parser]
          parser = parser_type.resolve.annotation(Simplell::ParserAttr).args[0]
          counter = parser[:rule_counter]
          parser[:rule_counter] = counter + 1
          rhs_vars = args.keys
        %}

        @[Simplell::RuleAttr({{ args.double_splat }})]
        def self.rule{{ counter }}({{ rhs_vars.join(",").id }}, lexer)
          {{ yield }}
        end
      {% end %}
    {% else %}
      {% raise "#{@type} is invalid symbol." %}
    {% end %} 
  end

  private macro build_ll_parser
    collect_symbols({{ @type }})
    build_first_set({{ @type }})
    build_follow_set({{ @type }})
    build_predict_set({{ @type }})
    build_topdown_parsing_visitor({{ @type }})
  end

  private macro collect_symbols(current_path)
    {% type = current_path.resolve %}
    {% if ann = type.annotation(Simplell::ParserAttr) %}
      {% parser = ann.args[0] %}
      {% if top_symbol = parser[:top_symbol] %}
        {% parser[:non_terminal_set] = { top_symbol.id => true } %}
        collect_symbols({{ current_path }}::{{ top_symbol }})
      {% else %}
        {% raise "Parser #{current_path} has no top symbol defined." %}
      {% end %}
    {% elsif ann = type.annotation(Simplell::SymbolAttr) %}
      {%
        parser_type = ann[:parser]
        parser = parser_type.resolve.annotation(Simplell::ParserAttr).args[0]
        symbol = current_path.names.last
        non_terminal_set = parser[:non_terminal_set]
        eplison = parser[:eplison]
      %}

      {% for method in type.class.methods %}
        {% if rule_ann = method.annotation(Simplell::RuleAttr) %}
          {% rhs_syms = rule_ann.named_args.values %}
          {% if rules = parser[:rules] %}
            {% rules << {lhs_path: current_path, name: method.name.symbolize, rhs: rhs_syms} %}
          {% else %}
            {% parser[:rules] = [{lhs_path: current_path, name: method.name.symbolize, rhs: rhs_syms}] %}
          {% end %}

          {% for rhs_sym in rhs_syms %}
            {% if rhs_sym.is_a?(Path) %}
              {% if rhs_sym == eplison %}
                {% if terminal_set = parser[:terminal_set] %}
                  {% terminal_set[rhs_sym] = true %}
                {% else %}
                  {% parser[:terminal_set] = { rhs_sym => true } %}
                {% end %}
              {% elsif !non_terminal_set[rhs_sym.id] %}
                {% non_terminal_set[rhs_sym.id] = true %}
                collect_symbols({{ parser_type }}::{{ rhs_sym }})
              {% end %}
            {% elsif terminal_set = parser[:terminal_set] %}
              {% terminal_set[rhs_sym] = true %}
            {% else %}
              {% parser[:terminal_set] = { rhs_sym => true } %}
            {% end %}
          {% end %}
        {% end %}
      {% end %}
    {% else %}
      {% raise "Discover invalid type #{parser_type} during collecting symbols." %}
    {% end %}
  end

  private macro copy_first_set(parser_type, dest_sym, src_sym, rule_name)
    {%
      parser_ann = parser_type.resolve.annotation(Simplell::ParserAttr)
      parser = parser_ann.args[0]
      tmps = parser_ann.args[1]

      non_terminal_set = parser[:non_terminal_set]
      terminal_set = parser[:terminal_set]
      eplison = parser[:eplison]

      rule_state_set = tmps[:rule_state_set]
    %}

    {% if rule_state_set[rule_name] == 0 %}
      {% if non_terminal_set[src_sym.id] %}
        {% if first_set = parser[:first_set] %}
          {% if src_set = first_set[src_sym.id] %}
            {% for src_terminal in src_set %}
              {% if dest_set = first_set[dest_sym.id] %}
                {% dest_set[src_terminal] = true %}
              {% else %}
                {% first_set[dest_sym.id] = { src_terminal => true } %}
              {% end %}
            {% end %}

            {% unless src_set[eplison] %}
              {% rule_state_set[rule_name] = 1 %}
            {% end %}
          {% end %}
        {% end %}
      {% else %}
        {% if first_set = parser[:first_set] %}
          {% if dest_set = first_set[dest_sym.id] %}
            {% dest_set[src_sym] = true %}
          {% else %}
            {% first_set[dest_sym.id] = { src_sym => true } %}
          {% end %}
        {% else %}
          {% parser[:first_set] = { dest_sym.id => { src_sym => true } } %}
        {% end %}

        {% unless src_sym == eplison %}
          {% rule_state_set[rule_name] = 1 %}
        {% end %}
      {% end %}
    {% end %}
  end

  private macro find_first_set(parser_type, target_sym, current_path)
    {%
      parser_ann = parser_type.resolve.annotation(Simplell::ParserAttr)
      parser = parser_ann.args[0]
      tmps = parser_ann.args[1]

      non_terminal_set = parser[:non_terminal_set]
      terminal_set = parser[:terminal_set]
      eplison = parser[:eplison]

      current_type = current_path.resolve
      current_sym = current_path.names.last

      visited_set = tmps[:visited_set]
      rule_state_set = tmps[:rule_state_set]
    %}

    {% unless visited_set[current_sym.id] %}
      {% visited_set[current_sym.id] = true %}

      {% for method in current_type.class.methods %}
        {% if rule_ann = method.annotation(Simplell::RuleAttr) %}
          {%
            rhs_syms = rule_ann.named_args.values
            method_name = method.name.symbolize
            rule_state_set[method_name] = 0
            state = 0
          %}

          {% for rhs_sym in rhs_syms %}
            {% if state == 0 %}
              {% if non_terminal_set[rhs_sym.id] %}
                find_first_set({{ parser_type }}, {{ current_sym }}, {{ parser_type }}::{{ rhs_sym }})
                {% if target_sym.id != current_sym.id %}
                  copy_first_set({{ parser_type }}, {{ target_sym }}, {{ current_sym }}, {{ method_name }})
                {% end %}
              {% else %}
                {% state = 1 %}
                copy_first_set({{ parser_type }}, {{ target_sym }}, {{ rhs_sym }}, {{ method_name }})
              {% end %}
            {% end %}
          {% end %}

          {% if state == 0 %}
            copy_first_set({{ parser_type }}, {{ target_sym }}, {{ eplison }}, {{ method_name }})
          {% end %}
        {% end %}
      {% end %}
    {% end %}
  end

  private macro reset_first_set_tmps(parser_type)
    {%
      parser_ann = parser_type.resolve.annotation(Simplell::ParserAttr)
      tmps = parser_ann.args[1]
      tmps[:visited_set] = { nil => nil }
      tmps[:rule_state_set] = { nil => nil }
    %}
  end

  private macro build_first_set(parser_type)
    {%
      parser = parser_type.resolve.annotation(Simplell::ParserAttr).args[0]
      non_terminal_set = parser[:non_terminal_set]
    %}

    {% for nt_sym in non_terminal_set.keys %}
      reset_first_set_tmps({{ parser_type }})
      find_first_set({{ parser_type }}, {{ nt_sym }}, {{ parser_type }}::{{ nt_sym }}) 
    {% end %}
  end

  private macro find_prefollow_set(parser_type, target_sym, current_sym)
    {%
      parser_ann = parser_type.resolve.annotation(Simplell::ParserAttr)
      parser = parser_ann.args[0]
      tmps = parser_ann.args[1]

      non_terminal_set = parser[:non_terminal_set]
      terminal_set = parser[:terminal_set]
      eplison = parser[:eplison]
      first_set = parser[:first_set]

      visited_set = tmps[:visited_set]
      prefollow_set = tmps[:prefollow_set]
    %}

    {% unless visited_set[current_sym.id] %}
      {% visited_set[current_sym.id] = true %}

      {% for rule in parser[:rules] %}
        {%
          lhs_path = rule[:lhs_path]
          lhs_sym = lhs_path.names.last
          rhs_syms = rule[:rhs]
          state = 0
        %}

        {% for rhs_sym in rhs_syms %}
          {% if rhs_sym.id == current_sym.id %}
            {% state = 1 %}
          {% elsif state == 1 %}
            {% if terminal_set[rhs_sym] %}
              {% if rhs_sym != eplison %}
                {% if dest_set = prefollow_set[target_sym.id] %}
                  {% dest_set[rhs_sym] = true %}
                {% else %}
                  {% prefollow_set[target_sym.id] = { rhs_sym => true } %}
                {% end %}

                {% state = 2 %}
              {% end %}
            {% else %}
              {% for src_sym in first_set[rhs_sym.id].keys %}
                {% if src_sym != eplison %}
                  {% if dest_set = prefollow_set[target_sym.id] %}
                    {% dest_set[src_sym] = true %}
                  {% else %}
                    {% prefollow_set[target_sym.id] = { src_sym => true } %}
                  {% end %}
                {% end %}
              {% end %}

              {% if first_set[rhs_sym.id][eplison] %}
                find_prefollow_set({{ parser_type }}, {{ target_sym }}, {{ rhs_sym }})

                {% if dest_set = prefollow_set[target_sym.id] %}
                  {% dest_set[rhs_sym.id] = true %} 
                {% else %}
                  {% prefollow_set[target_sym.id] = { rhs_sym.id => true } %} 
                {% end %}
              {% else %}
                {% state = 2 %}
              {% end %}  
            {% end %}
          {% end %}
        {% end %}

        {% if state == 1 %}
          find_prefollow_set({{ parser_type }}, {{ target_sym }}, {{ lhs_sym }})

          {% if dest_set = prefollow_set[target_sym.id] %}
            {% dest_set[lhs_sym.id] = true %}
          {% else %}
            {% prefollow_set[target_sym.id] = { lhs_sym.id => true } %}
          {% end %}
        {% end %}
      {% end %}
    {% end %}
  end

  private macro reset_follow_set_tmps(parser_type)
    {%
     parser_ann = parser_type.resolve.annotation(Simplell::ParserAttr)
      tmps = parser_ann.args[1]
      tmps[:visited_set] = { nil => nil }
    %}
  end

  private macro find_follow_set(parser_type, target_sym, current_sym)
    {%
      parser_ann = parser_type.resolve.annotation(Simplell::ParserAttr)
      parser = parser_ann.args[0]
      tmps = parser_ann.args[1]

      non_terminal_set = parser[:non_terminal_set]
      terminal_set = parser[:terminal_set]
      eplison = parser[:eplison]
      first_set = parser[:first_set]
      follow_set = parser[:follow_set]

      visited_set = tmps[:visited_set]
      prefollow_set = tmps[:prefollow_set]
    %}

    {% unless visited_set[current_sym.id] %}
      {% visited_set[current_sym.id] = true %}

      {% for pf_sym in prefollow_set[current_sym.id] %}
        {% if non_terminal_set[pf_sym.id] %}
          find_follow_set({{ parser_type }}, {{ target_sym }}, {{ pf_sym }})
        {% else %}
          {% if dest_set = follow_set[target_sym.id] %}
            {% dest_set[pf_sym] = true %}
          {% else %}
            {% follow_set[target_sym.id] = { pf_sym => true } %}
          {% end %}
        {% end %}
      {% end %}
    {% end %}
  end

  private macro build_follow_set(parser_type)
    {%
      parser_ann = parser_type.resolve.annotation(Simplell::ParserAttr)
      parser = parser_ann.args[0]
      tmps = parser_ann.args[1]

      non_terminal_set = parser[:non_terminal_set]
      end_marker = parser[:end_marker]
      top_symbol = parser[:top_symbol]

      parser[:follow_set] = { top_symbol.id => { end_marker => true } }
      tmps[:prefollow_set] = { top_symbol.id => { end_marker => true } }
    %}

    {% for nt_sym in non_terminal_set.keys %}
      reset_follow_set_tmps({{ parser_type }})
      find_prefollow_set({{ parser_type }}, {{ nt_sym }}, {{ nt_sym }})
    {% end %}

    {% for nt_sym in non_terminal_set.keys %}
      reset_follow_set_tmps({{ parser_type }})
      find_follow_set({{ parser_type }}, {{ nt_sym }}, {{ nt_sym }})
    {% end %}
  end

  private macro add_predict_set(parser_type, target_sym, terminal_sym, idx)
    {% parser = parser_type.resolve.annotation(Simplell::ParserAttr).args[0] %}
    {% if predict_set = parser[:predict_set] %}
      {% if dest_set = predict_set[target_sym.id] %}
        {% unless dest_set[terminal_sym] %}
          {% dest_set[terminal_sym] = idx %}
        {% end %}
      {% else %}
        {% predict_set[target_sym.id] = { terminal_sym => idx } %}
      {% end %}
    {% else %}
      {% parser[:predict_set] = { target_sym.id => { terminal_sym => idx } } %}
    {% end %}
  end

  private macro build_predict_set(parser_type)
    {%
      parser_ann = parser_type.resolve.annotation(Simplell::ParserAttr)
      parser = parser_ann.args[0]

      non_terminal_set = parser[:non_terminal_set]
      terminal_set = parser[:terminal_set]
      eplison = parser[:eplison]
      first_set = parser[:first_set]
      follow_set = parser[:follow_set]
    %}

    {% for rule, idx in parser[:rules] %}
      {%
        lhs_path = rule[:lhs_path]
        lhs_sym = lhs_path.names.last
        rhs_syms = rule[:rhs]
        state = 0
      %}

      {% for rhs_sym in rhs_syms %}
        {% if state == 0 %}
          {% if terminal_set[rhs_sym] %}
            {% if rhs_sym != eplison %}
              add_predict_set({{ parser_type }}, {{ lhs_sym }}, {{ rhs_sym }}, {{ idx }})
              {% state = 1 %}
            {% end %} 
          {% else %}
            {% for rf_sym in first_set[rhs_sym.id].keys %}
              {% if rf_sym != eplison %}
                add_predict_set({{ parser_type }}, {{ lhs_sym }}, {{ rf_sym }}, {{ idx }})
              {% end %}
            {% end %}

            {% unless first_set[rhs_sym.id][eplison] %}
              {% state = 1 %}
            {% end %}
          {% end %}
        {% end %}
      {% end %}

      {% if state == 0 %}
        {% for rfo_sym in follow_set[lhs_sym.id].keys %}
          add_predict_set({{ parser_type }}, {{ lhs_sym }}, {{ rfo_sym }}, {{ idx }}) 
        {% end %}
      {% end %}
    {% end %}
  end

  private macro expect_terminal_symbol(sym, lexer)
    {% if sym.is_a?(CharLiteral) %}
      (lexer.peek == {{ sym }})
    {% elsif sym.is_a?(Path) %}
      lexer.peek.is_a?({{ sym }})
    {% else %}
      {% raise "Unsupport terminal symbol #{sym}" %}
    {% end %}
  end

  private macro shift_terminal_symbol(sym, lexer)
    {% if sym.is_a?(CharLiteral) %}
      lexer.peek.tap do |%t|
        if %t == {{ sym }}
          lexer.shift
        else
          raise Simplell::SyntaxError.new {{ "expect '#{sym}', but " }} + "'#{%t}'"
        end
      end
    {% else %}
      {% raise "Unsupport terminal symbol #{sym}" %}
    {% end %}
  end

  private macro build_topdown_parsing_visitor(parser_type)
    {%
      parser = parser_type.resolve.annotation(Simplell::ParserAttr).args[0]
      non_terminal_set = parser[:non_terminal_set]
      terminal_set = parser[:terminal_set]
      eplison = parser[:eplison]
      predict_set = parser[:predict_set]
      top_symbol = parser[:top_symbol]
      rules = parser[:rules]
    %}

    def self.parse(lexer)
      visit_{{ top_symbol }}(lexer)
    end

    {% for nt_sym in non_terminal_set.keys %}
      private def self.visit_{{ nt_sym }}(lexer)
        {% for sym, rule_idx in predict_set[nt_sym.id] %}
          {%
            rule = rules[rule_idx]
            lhs_path = rule[:lhs_path]
            name = rule[:name]
            rhs_syms = rule[:rhs]
            production = "#{nt_sym} -> " + rhs_syms.join(' ')
          %}

          {{ ("# " + production).id }}
          if (expect_terminal_symbol({{ sym }}, lexer))
            {% if rhs_syms[0] != eplison %}
              return {{ lhs_path }}.{{ name.id }}(
              {% for rhs_sym, rhs_sym_idx in rhs_syms %}
                {% if non_terminal_set[rhs_sym.id] %}
                  visit_{{ rhs_sym }}(lexer),
                {% else %}
                  shift_terminal_symbol({{ rhs_sym }}, lexer),
                {% end %}
              {% end %}
              lexer)
            {% else %}
              return {{ lhs_path }}.{{ name.id }}(nil, lexer)
            {% end %}
          end
        {% end %}

        raise Simplell::SyntaxError.new "invalid token #{lexer.peek}"
      end
    {% end %}
  end
end
