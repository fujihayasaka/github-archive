#!/usr/bin/env ruby
#/ Usage: script/delete-feature-flag <feature-flag-name>
# frozen_string_literal: true

require "rubocop"
require "rubocop-ast"
require "gh/dev/rubocop_ast"

class FeatureFlagTerminator
  def initialize(feature_flag)
    @feature_flag = feature_flag

    # Regex for AST-based matching (Ruby code) - uses lookahead to avoid capturing extra chars
    @contains_enabled_regexp = %r{
      FeatureFlag\.vexi\.enabled\?\(\s*['"]#{feature_flag}['"](?=[,\s\)])
      |FeatureFlag\.vexi\.enabled\?\(\s*:#{feature_flag}(?=[,\s\)])
      |FeatureFlag\.vexi\.enabled_with_details\(\s*['"]#{feature_flag}['"](?=[,\s\)])
      |FeatureFlag\.vexi\.enabled_with_details\(\s*:#{feature_flag}(?=[,\s\)])
      |FeatureFlag\.vexi\.enabled_or_raise\?\(\s*['"]#{feature_flag}['"](?=[,\s\)])
      |FeatureFlag\.vexi\.enabled_or_raise\?\(\s*:#{feature_flag}(?=[,\s\)])
      |\.vexi\.enabled\?\(\s*['"]#{feature_flag}['"](?=[,\s\)])
      |\.vexi\.enabled\?\(\s*:#{feature_flag}(?=[,\s\)])
      |\.vexi\.enabled_with_details\(\s*['"]#{feature_flag}['"](?=[,\s\)])
      |\.vexi\.enabled_with_details\(\s*:#{feature_flag}(?=[,\s\)])
      |\.vexi\.enabled_or_raise\?\(\s*['"]#{feature_flag}['"](?=[,\s\)])
      |\.vexi\.enabled_or_raise\?\(\s*:#{feature_flag}(?=[,\s\)])
      |\w+.?user_feature_enabled\?[\(\s]:#{feature_flag}\)?
      |feature_enabled_for_user_or_current_visitor\?[\(\s]feature_name:\s?:#{feature_flag}\)?
      |feature_enabled_globally_or_for_user\?[\(\s]feature_name:\s?:#{feature_flag}\)?
      |feature_preview_enabled\?\(:#{feature_flag}?
      |.*feature_enabled\?\(:#{feature_flag}?
      |.*feature_flag_enabled\?\(:#{feature_flag}?
    }x

    # Regex for ERB templates - matches complete method calls
    @erb_enabled_regexp = %r{
      FeatureFlag\.vexi\.enabled\?\(\s*['"]#{feature_flag}['"][^\)]*\)
      |FeatureFlag\.vexi\.enabled\?\(\s*:#{feature_flag}[^\)]*\)
      |FeatureFlag\.vexi\.enabled_with_details\(\s*['"]#{feature_flag}['"][^\)]*\)\.result
      |FeatureFlag\.vexi\.enabled_with_details\(\s*:#{feature_flag}[^\)]*\)\.result
      |FeatureFlag\.vexi\.enabled_with_details\(\s*['"]#{feature_flag}['"][^\)]*\)
      |FeatureFlag\.vexi\.enabled_with_details\(\s*:#{feature_flag}[^\)]*\)
      |FeatureFlag\.vexi\.enabled_or_raise\?\(\s*['"]#{feature_flag}['"][^\)]*\)
      |FeatureFlag\.vexi\.enabled_or_raise\?\(\s*:#{feature_flag}[^\)]*\)
      |\.vexi\.enabled\?\(\s*['"]#{feature_flag}['"][^\)]*\)
      |\.vexi\.enabled\?\(\s*:#{feature_flag}[^\)]*\)
      |\.vexi\.enabled_with_details\(\s*['"]#{feature_flag}['"][^\)]*\)\.result
      |\.vexi\.enabled_with_details\(\s*:#{feature_flag}[^\)]*\)\.result
      |\.vexi\.enabled_with_details\(\s*['"]#{feature_flag}['"][^\)]*\)
      |\.vexi\.enabled_with_details\(\s*:#{feature_flag}[^\)]*\)
      |\.vexi\.enabled_or_raise\?\(\s*['"]#{feature_flag}['"][^\)]*\)
      |\.vexi\.enabled_or_raise\?\(\s*:#{feature_flag}[^\)]*\)
      |\w+.?user_feature_enabled\?[\(\s]:#{feature_flag}\)?
      |feature_enabled_for_user_or_current_visitor\?[\(\s]feature_name:\s?:#{feature_flag}\)?
      |feature_enabled_globally_or_for_user\?[\(\s]feature_name:\s?:#{feature_flag}\)?
      |feature_preview_enabled\?\(:#{feature_flag}?
      |.*feature_enabled\?\(:#{feature_flag}?
      |.*feature_flag_enabled\?\(:#{feature_flag}?
    }x

    @starts_with_enabled_regexp = /^#{@contains_enabled_regexp}/
  end

  def delete_from_ruby_code(code)
    @lines_to_delete = []
    @lines_to_indent = []

    source = GH::Dev::RuboCopAst.processed_source(code)
    @rewriter = Parser::Source::TreeRewriter.new(source.buffer)

    source.ast.each_node do |node|
      if flag_enabled_node?(node)
        rewrite_flag_enabled_node(node)
      elsif action = toggle_node?(node)
        if action == "enable"
          delete_code(node.loc.expression)
        else
          @rewriter.replace(node.loc.expression, "# DELETED: #{node.source}")
        end
      end
    end

    format_output
  end

  def delete_from_erb_template(code)
    code.gsub(@erb_enabled_regexp, "true")
  end

  private

  def send_type?(node)
    node.send_type? || node.csend_type?
  end

  def flag_enabled_node?(node)
    return false unless send_type?(node) # quick check to avoid using regexps in every node
    @starts_with_enabled_regexp.match(node.source)
  end

  def rewrite_flag_enabled_node(node)
    parent = node.parent
    if (parent.and_type? || parent.or_type?) && parent.children.size == 2
      rewrite_flag_enabled_node_binary_bool_expression(node)
    elsif parent.if_type?
      if parent.if?
        rewrite_flag_enabled_if(node)
      elsif parent.unless?
        rewrite_flag_enabled_unless(node)
      end
    else
      @rewriter.replace(node.loc.expression, "true")
    end
  end

  def rewrite_flag_enabled_node_binary_bool_expression(node)
    parent = node.parent
    # For && or || expression with only two items, we want to only leave the other item
    other = parent.children.first == node ? parent.children.last : parent.children.first
    # If the expression was around (), we want to delete them too
    parent = parent.parent if parent.parent.begin_type?
    @rewriter.replace(parent.loc.expression, other.source)
  end

  def rewrite_flag_enabled_if(node)
    parent = node.parent
    # For an IF with just the FF check, we want to delete the expression and the ELSE
    delete_code(parent.loc.keyword, parent.children.first.loc.expression)

    if parent.loc.respond_to?(:else) && parent.loc.else
      delete_code(parent.loc.else, parent.loc.end)
      add_lines_to_indent(parent.loc.expression.line + 1, parent.loc.else.line - 1)
    elsif parent.loc.end
      delete_code(parent.loc.end)
      add_lines_to_indent(parent.loc.expression.line + 1, parent.loc.end.line - 1)
    end
  end

  def rewrite_flag_enabled_unless(node)
    parent = node.parent
    # For an UNLESS with just the FF check, we want to delete the expression and the first block
    if parent.loc.respond_to?(:else) && parent.loc.else
      delete_code(parent.loc.expression, parent.loc.else)
      delete_code(parent.loc.end)
      add_lines_to_indent(parent.loc.else.line + 1, parent.loc.end.line - 1)
    else
      delete_code(parent.loc.expression)
    end
  end

  def toggle_node?(node)
    return false unless send_type?(node) # quick check to avoid using regexps in every node
    regexes = [
      # VexiManagement methods
      /FeatureFlag\.vexi_management\.(?<action>enable|disable)_feature_flag\(\s*['":](?<flag>\w+)/,
      /FeatureFlag\.vexi_management\.add_feature_flag_actors\(\s*['":](?<flag>\w+)/,
      /FeatureFlag\.vexi_management\.remove_feature_flag_actors\(\s*['":](?<flag>\w+)/,
      # Test helper methods
      /.*(?<action>enable|disable)_feature_flag\(\s*['":](?<flag>\w+)/,
      # Legacy methods
      /.*(?<action>enable|disable)_feature\(:(?<flag>\w+)\)/,
    ]
    match = regexes.lazy.filter_map { |regex| regex.match(node.source) }.first
    return false if match.nil?
    if match.names.include?("flag") && match[:flag] == @feature_flag
      if match.names.include?("action")
        return match[:action]
      else
        # For add_feature_flag_actors, treat as "enable" to delete them
        # For remove_feature_flag_actors, treat as "disable" to comment them
        return node.source.include?("remove_feature_flag_actors") ? "disable" : "enable"
      end
    end
    false
  end

  def delete_code(from, to = from)
    range = Parser::Source::Range.new(@rewriter.source_buffer, from.begin_pos, to.end_pos)
    @rewriter.replace(range, empty_lines(to.line - from.line))
    add_lines_to_delete(from.line, to.line)
  end

  def empty_lines(n)
    " \n" * n
  end

  def add_lines(arr, from, to)
    while from <= to
      arr.unshift(from)
      from += 1
    end
  end

  def add_lines_to_delete(from, to)
    add_lines(@lines_to_delete, from, to)
  end

  def add_lines_to_indent(from, to)
    add_lines(@lines_to_indent, from, to)
  end

  def format_output
    lines = @rewriter.process.split("\n")
    lines << ""
    @lines_to_indent.each do |line|
      lines[line - 1] = lines[line - 1].delete_prefix "  "
    end
    @lines_to_delete.each do |line|
      previous_line = lines[line - 1]
      lines.delete_at(line - 1) if previous_line&.strip&.empty?
    end
    lines.join("\n")
  end
end

if __FILE__ == $0
  feature_flag = ARGV.shift

  patterns = [/:#{feature_flag}/]
  dirs = %w[test app config jobs lib packages]

  terminator = FeatureFlagTerminator.new(feature_flag)

  pattern_args = patterns.flat_map { |pattern| ["-e", pattern.respond_to?(:source) ? pattern.source : pattern] }
  args = %w[
    --files-with-matches
    --no-index
    --extended-regexp
    --word-regexp
  ]
  cmd = ["git", "grep", *args, *pattern_args, "--", *dirs]

  paths = IO.popen(cmd).read.split("\n")
  paths.each do |path|
    puts "Processing #{path}"
    code = File.open(path).read
    if path.end_with? ".rb"
      File.write(path, terminator.delete_from_ruby_code(code))
    elsif path.end_with? ".erb"
      File.write(path, terminator.delete_from_erb_template(code))
    else
      puts "Unsupported file format #{path}"
    end
  end
end
