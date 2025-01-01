# typed: strict
# frozen_string_literal: true

module Api::App::DiffContentsDependency
  extend T::Sig
  extend T::Helpers

  requires_ancestor { Api::App }

  # Provides basic GitRPC error handling when rendering raw diff content.
  sig { params(medias: Api::AcceptedMediaTypes, block: T.proc.returns(T.untyped)).returns(T.untyped) }
  def delivering_raw_diff_content(medias, &block)
    return unless block.respond_to?(:call)

    begin
      block.call
    rescue GitRPC::ObjectMissing, GitRPC::InvalidObject
      deliver_error! 404
    rescue GitRPC::Timeout
      reason = if medias.api_param?(:diff)
        "diff"
      elsif medias.api_param?(:patch)
        "patch"
      else
        "request"
      end
      deliver_error! 422, message: "The #{reason} is taking too long to generate."
    end
  end

  sig { params(resource_type: Symbol, diff: GitHub::Diff).void }
  def deliver_undiffable_error!(resource_type, diff)
    valid_resource_types = [:PullRequest, :Commit, :Comparison]

    unless valid_resource_types.include?(resource_type)
      raise ArgumentError, "resource_type must be one of #{valid_resource_types}"
    end

    message = \
      if diff.corrupt?
        "Server Error: Sorry, there was a problem generating this diff. The repository may be missing relevant data."
      elsif diff.too_busy?
        "Server Error: Sorry, this diff is temporarily unavailable due to heavy server load."
      elsif diff.missing_commits?
        "Sorry, there was a problem generating this diff. The repository may be missing relevant data."
      elsif diff.truncated_for_max_lines?
        "Sorry, the diff exceeded the maximum number of lines (#{diff.max_total_lines})"
      elsif diff.truncated_for_max_files?
        "Sorry, the diff exceeded the maximum number of files (#{diff.max_files}). Consider using 'List pull requests files' API or locally cloning the repository instead."
      else
        "Server Error: Sorry, this diff is taking too long to generate."
      end

    api_error_type = if diff.truncated_for_max_lines? || diff.truncated_for_max_files?
      :too_large
    else
      :not_available
    end

    response = {
      message: message,
      errors: [api_error(resource_type, :diff, api_error_type)],
    }

    response[:documentation_url] = if diff.corrupt? || diff.missing_commits?
      "/v3/pulls#diff-error"
    elsif diff.truncated_for_max_files?
      "/rest/pulls/pulls#list-pull-requests-files"
    end

    # Don't report errors for missing commits. This is a valid state and would flood failbot if reported.
    # If there is no error, then the diff is either on a null git object or the unavailable reason
    # is cached and not worth reporting to Failbot.
    if !diff.missing_commits? && diff.unavailable_error
      Failbot.report(diff.unavailable_error)
    end

    response_code = \
      # There are valid scenarios in which a pull request cannot be viewed due to missing commits.
      # For example the branch could have been force pushed so that it no longer shares a common
      # merge base with the base branch, or perhaps the head commit was removed due to a privacy
      # violation. These cases are not considered server errors.
      if diff.missing_commits?
        422
      elsif diff.timed_out? || diff.truncated_for_timeout?
        422
      elsif diff.truncated_for_max_lines? || diff.truncated_for_max_files?
        406
      else
        500
      end

    GitHub.logger.info(
      message,
      "code.function" => "deliver_undiffable_error",
      "http.response.status_code" => response_code,
      "gh.diff.unavailable_reason" => diff.unavailable_reason,
      "gh.diff.resource_type" => resource_type,
    )

    GitHub.dogstats.increment("diff.unavailable_reason", tags: ["resource:#{resource_type}", "reason:#{diff.unavailable_reason}"]) if diff.unavailable_reason

    deliver_error! response_code, response
  end
end
