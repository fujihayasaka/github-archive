# typed: true
# frozen_string_literal: true

module CompareHelper
  include ActionView::Helpers::UrlHelper
  include UrlHelper

  extend T::Helpers

  COMMIT_LIMIT_FOR_TABS = 20

  # Return an array with several 'sample comparisons' that could be
  # useful to the user as a starting point.
  #
  # We use a pretty simple heuristic: return the newest 20 branches,
  # based on the time of their newest commit, prioritizing them by
  # whether they have Pull Requests or not (we want branches without
  # pull requests, if possible, because they make a better example).
  #
  # This is cached by GitRPC in 1h intervals, but regardless should
  # be pretty fast.
  def sample_comparisons(repository)
    base_tree = repository.default_branch
    interesting = repository.rpc.interesting_branches(base_tree, 5)
    branches_to_exclude = repository.branches_being_renamed
    interesting = interesting.reject do |_timestamp, _, branch_name|
      branches_to_exclude.include?(branch_name)
    end

    interesting.collect do |timestamp, _, ref|
      {
        label: ref.try { |r| r.force_encoding("utf-8").scrub! },
        range: "#{base_tree}...#{ref}".dup.force_encoding("utf-8"),
        pushed_at: Time.at(timestamp),
      }
    end
  end

  # Public: Generate label for comparison base.
  #
  # If the comparison is cross repository, then the full label including
  # username is shown, "<user>:<ref>". Otherwise just the "<ref>" itself.
  #
  # comparison - A Comparison
  #
  # Returns String.
  def comparison_base_ref_label(comparison)
    if comparison.cross_repository?
      comparison.display_qualified_base_revision
    else
      comparison.display_base_revision
    end
  end

  # Public: Generate label for comparison head.
  #
  # If the comparison is cross repository, then the full label including
  # username is shown, "<user>:<ref>". Otherwise just the "<ref>" itself.
  #
  # comparison - A Comparison
  #
  # Returns String.
  def comparison_head_ref_label(comparison)
    if comparison.cross_repository?
      comparison.display_qualified_head_revision
    else
      comparison.display_head_revision
    end
  end

  # Public: Generate comparison path with base repository.
  #
  # comparison - A Comparison
  # repository - A new base Repository
  #
  # Returns String path.
  def base_repo_comparison_path(comparison, repository, expand: false)
    base = revision_path(comparison.base_repo&.owner, repository.user.display_login, repository.name, comparison.base_ref)
    dots = comparison.direct_compare? ? ".." : "..."
    compare_path(comparison.repo, "#{base.try(:b)}#{dots}#{comparison.head.try(:b)}", expand: expand)
  end

  # Public: Generate comparison path with head repository.
  #
  # comparison - A Comparison
  # repository - A new head Repository
  #
  # Returns String path.
  def head_repo_comparison_path(comparison, repository, expand: false)
    head = revision_path(comparison.base_repo&.owner, repository.user.display_login, repository.name, comparison.head_ref)
    dots = comparison.direct_compare? ? ".." : "..."
    compare_path(comparison.repo, "#{comparison.base.try(:b)}#{dots}#{head.try(:b)}", expand: expand)
  end

  # Public: Generate comparison path with new base ref name.
  #
  # comparison - A Comparison
  # base - New String base ref name
  #
  # Returns String path.
  def base_ref_comparison_path(comparison, base, expand: false)
    if comparison.base.to_s.include?(":")
      base = revision_path(comparison.base_repo&.owner, comparison.base_user_login, comparison.base_repo&.name, base)
      base = base.b if base
    end

    head = comparison.head.b if comparison.head
    dots = comparison.direct_compare? ? ".." : "..."
    compare_path(comparison.repo, "#{base}#{dots}#{head}", expand: expand)
  end

  # Public: Generate comparison path with new head ref name.
  #
  # comparison - A Comparison
  # head - New String head ref name
  #
  # Returns String path.
  def head_ref_comparison_path(comparison, head, expand: false)
    if comparison.head.to_s.include?(":")
      head = revision_path(comparison.base_repo&.owner, comparison.head_user_login, comparison.head_repo&.name, head)
      head = head.b if head
    end

    base = comparison.base.b if comparison.base
    dots = comparison.direct_compare? ? ".." : "..."
    compare_path(comparison.repo, "#{base}#{dots}#{head}", expand: expand)
  end

  # Generate a user-readable string explaining the ahead-behind
  # relationship between two branches.
  #
  # Examples (note the impeccable use of English grammar):
  #
  # compare_ahead_behind_text(4, 0, base_branch: 'foo')
  # #=> '4 commits ahead of foo'
  #
  # compare_ahead_behind_text(4, 2, base_branch: 'foo')
  # #=> '5 commits ahead, 2 commits behind foo'
  #
  # compare_ahead_behind_text(0, 2, base_branch: 'foo')
  # #=> '2 commits behind foo'
  #
  # compare_ahead_behind_text(0, 0, base_branch: 'foo')
  # #=> 'even with foo'
  #
  # Returns a String.
  def compare_ahead_behind_text(ahead, behind, base_branch: nil, ahead_link: nil, ahead_link_attributes: nil, behind_link: nil, behind_link_attributes: nil)
    trailer = "".dup
    encoded_base_branch = base_branch.dup.force_encoding("utf-8").scrub if base_branch

    if ahead.nil? || behind.nil?
      ""
    elsif ahead == 0 && behind == 0
      trailer << " with #{encoded_base_branch}" if base_branch
      "up to date" + trailer
    else
      if base_branch
        trailer << " of" if behind == 0
        trailer << " #{encoded_base_branch}"
      end

      if !ahead_link || !behind_link
        chunks = []
        chunks << "#{ahead} #{'commit'.pluralize(ahead)} ahead" if ahead > 0
        chunks << "#{behind} #{'commit'.pluralize(behind)} behind" if behind > 0
        chunks.join(", ") + trailer
      else
        ahead_link = link_to("#{ahead} #{'commit'.pluralize(ahead)} ahead", ahead_link, ahead_link_attributes)
        behind_link = link_to("#{behind} #{'commit'.pluralize(behind)} behind", behind_link, behind_link_attributes)

        content_tag(:span) do
          if ahead > 0 && behind > 0
            ahead_link + ", " + behind_link + trailer
          elsif ahead > 0
            ahead_link + trailer
          else
            behind_link + trailer
          end
        end
      end
    end
  end

  def render_tabs_on_compare?(comparison)
    !comparison.direct_compare? && comparison.common_ancestor? && comparison.commits.size > COMMIT_LIMIT_FOR_TABS
  end

  # Generate either user:repo_name:ref_name or user:ref_name
  #
  # Owner - Account to check FF on
  # user_name - User or Org Name
  # repo_name - Name of Repository
  # ref_name - Name of Ref
  #
  # Returns a String.
  def revision_path(owner, user_name, repo_name, ref_name)
    if repo_name.present?
      return [user_name, repo_name, ref_name].join(":")
    end

    [user_name, ref_name].join(":")
  end
end
