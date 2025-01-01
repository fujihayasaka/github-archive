# typed: true
# frozen_string_literal: true

class SyntaxHighlightedDiffEntriesController < GitContentController
  rescue_from InvalidParameterError, with: :render_400

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Memex,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Iam,
    ApplicationRecord::Copilot,
    ApplicationRecord::Notify,
    optional: true, only: [:index]

  def index
    sha1, sha2 = params[:range].split("..", 2)
    diff = GitHub::Diff.new(current_repository, sha1, sha2, diff_options)

    entries_by_path = diff.entries.index_by { |entry| entry.a_path || entry.b_path }

    highlighter = ::SyntaxHighlightedDiff.new(current_repository)
    highlighter.highlight!(diff.entries)

    render json: paths.to_unsafe_hash.each_with_object({}) { |(key, path), payload|
      entry = entries_by_path[path]

      if entry.present?
        parsed_lines = GitHub::Diff::RelatedLinesEnumerator.new(entry.lines)
        cache_code, highlighted_lines = highlighter.frozen_colorized_lines_with_cache_code(entry)

        payload[key] = parsed_lines.map do |line|
          HighlightedDiffLine.for_line(line, html_lines: highlighted_lines, cache_code: cache_code).as_json
        end
      end
    }
  rescue GitRPC::Failure, GitRPC::ObjectMissing
    # Transform low-level errors:
    #
    #   GitRPC::ObjectMissing: object not found
    #   GitRPC::Failure: Rugged::OdbError: odb: cannot read object: null OID cannot exist
    #
    # into something suitable for inclusion in error response.
    raise InvalidParameterError, "Invalid Git object"
  rescue ActionController::ParameterMissing
    head :bad_request
  end

  private

  def diff_options
    options = {
      paths: paths.values,
      ignore_whitespace: params[:whitespace_ignored] == "true",
      context_lines: context_lines,
    }

    base_sha = params[:base_sha]
    if base_sha && GitRPC::Util.valid_full_sha1?(base_sha)
      options[:base_sha] = base_sha
    end

    options
  end

  def context_lines
    context_lines_by_path = Hash.new { |h, k| h[k] = [] }

    params.required(:items).permit!.each do |_, item|
      next unless item[:context_lines]
      path = item[:path]
      lines = JSON.parse(item[:context_lines])

      context_lines_by_path[path] = lines.map do |range|
        if range =~ /\A(-?\d+)(\.{2,3})(-?\d+)\z/
          Range.new($1.to_i, $3.to_i, $2.length == 3)
        else
          raise InvalidParameterError, "Invalid range in context_lines: #{range.inspect}"
        end
      end
    end

    context_lines_by_path
  rescue JSON::ParserError
    raise InvalidParameterError, "Invalid context_lines"
  end

  def paths
    params.required(:items).permit!.transform_values { |item| item[:path] }
  end

  def render_400(error)
    render json: { error: error.message }, status: :bad_request
  end
end
