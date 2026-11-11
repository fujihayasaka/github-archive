# typed: true
# frozen_string_literal: true

module RepositoryContributorHelper
  extend T::Helpers

  include ApplicationHelper

  abstract!

  sig { abstract.returns(::Repository) }
  def current_repository; end

  sig { abstract.returns(::User) }
  def current_user; end

  sig { abstract.returns(T::Boolean) }
  def logged_in?; end

  sig { abstract.params(args: T.untyped).returns(String) }
  def repository_security_policy_path(*args); end

  def show_first_time_contributor_sidebar_for?(contribution_type:)
    return false unless logged_in?
    return false if current_repository.private? && !GitHub.enterprise?
    return false if current_repository.member?(current_user)
    return false if current_repository.owner == current_user
    !current_repository.contributor?(current_user, type: contribution_type)
  end

  def has_community_guidelines_files?
    [contributing_file, code_of_conduct_file, security_policy_file, support_file].any?
  end

  def contributing_file
    return @contributing_file if defined?(@contributing_file)
    @contributing_file = current_repository.preferred_files
      .fetch(:contributing)&.permalink
  end

  def code_of_conduct_file
    return @code_of_conduct_file if defined?(@code_of_conduct_file)
    @code_of_conduct_file = current_repository.preferred_files
      .fetch(:code_of_conduct)&.permalink
  end

  def security_policy_file
    return @security_policy_file if defined?(@security_policy_file)
    @security_policy_file = if current_repository.security_policy.exists?
      repository_security_policy_path(current_repository.owner, current_repository)
    end
  end

  def support_file
    return @support_file if defined?(@support_file)
    @support_file = preferred_file_path(type: :support, repository: current_repository)
  end
end
