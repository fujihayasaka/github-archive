# typed: true
# frozen_string_literal: true

require "yaml"
require "json"
require "mustache"

class StacksMustache < Mustache
  class StacksMustacheTemplate < Mustache::Template
    def tokens(src = @source)
      parser = Mustache::Parser.new(@options)
      parser.otag = "${{"
      parser.compile(src)
    end
  end

  def context
    super
  end

  def self.templateify(obj, options = {})
    template = obj.is_a?(StacksMustacheTemplate) ? obj : StacksMustacheTemplate.new(obj, options)
  end

  def self.render(expression, replacement_context = {})
    # change from default mustache tag to ${{ }} just when using this function
    new.render(expression, replacement_context)
  end

  def render(expression, replacement_context = {}, raise_on_context_miss = true)
    replacement_context = replacement_context.merge(helper_method(context))
    self.raise_on_context_miss = raise_on_context_miss
    super(expression, replacement_context)
  end

  protected

  def helper_method(context)
    Hash[
        "If" => lambda do |expression| if_helper(expression) end,
        "IsNotArray" => lambda do |expression| is_not_array_helper(expression) end,
        "ExpandToYaml" => lambda do |expression| expand_to_yaml_helper(expression) end
    ]
  end

  def if_helper(expression)
    parts = condition_expressions(expression)
    return "\n" if parts.size < 2 || (self.render(parts[0], context.current, false)).blank?

    rem = expression.lstrip.sub("'" + parts[0] + "'", "").strip.delete_prefix("\n")
    "#{self.render(rem, context.current)}\n"
  end

  def is_not_array_helper(expression)
    parts = condition_expressions(expression)

    return "" if parts.size < 1

    rendered_part = self.render(parts[0], context.current)

    if JSON.parse(rendered_part.gsub("=>", ":").gsub(":nil,", ":null,")).kind_of?(Array)
      ""
    else
      self.render(parts[1..-1].join(""), context.current)
    end
  end

  def expand_to_yaml_helper(expression)
    rendered_string = self.render(expression, context.current)

    return "" if rendered_string.nil? || rendered_string.strip.empty?

    JSON.parse(rendered_string.gsub("=>", ":").gsub(":nil", ":null"))
        .to_yaml.delete_prefix("---\n").indent(rendered_string[/\A */].size)
  end

  def condition_expressions(text)
    parts = []
    fetch_parts_regex = Regexp.new(/[\'](.+?)[\']|[^ ]+/)
    idx = 0

    while (match_data = fetch_parts_regex.match(text, idx)) != nil
      part = (match_data[1].blank? ? match_data[0] : match_data[1])
      if part == "''"
        part = ""
      end
      parts.append(part)
      idx = match_data.end(0) + 1
    end

    parts
  end
end
