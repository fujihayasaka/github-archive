# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

class RepositorySetCommunityHealthFlagsJob < ApplicationJob
  queue_as :detect_community_health_files
  retry_on_dirty_exit

  def perform(repository_id, track_private_to_public = false)
    repository = Repository.find_by_id(repository_id)
    return unless repository

    profile = repository.community_profile || CommunityProfile.new(repository: repository)

    %i(readme code_of_conduct contributing).each do |file|
      file_contents = repository.public_send("preferred_#{file}")
      file_not_empty = file_contents && file_contents.info["data"].present?
      profile.public_send "has_#{file}=", !!file_not_empty
    end
    # We don't look at the license contents because they're manipulated by the licensee gem
    profile.public_send "has_license=", !!repository.public_send("preferred_license")
    code_of_conduct = CodeOfConduct.detect(repository)

    profile.assign_attributes({
      detected_code_of_conduct:             (code_of_conduct.legacy_key if code_of_conduct),
      has_docs:                             !!profile.documentation_url,
      has_description:                      !!repository.description,
      has_issue_opened_by_non_collaborator: !!profile.has_issue_from_non_collaborator?,
      has_pr_or_issue_template:             !!(profile.issue_template || profile.pr_template),
      has_outside_contributors:             !!profile.has_outside_contribution?,
    })

    begin
      with_write { profile.save! }
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      return false
    end

    return profile unless track_private_to_public

    tags = profile.attributes.select { |k, _v| k.starts_with? "has_" }.map { |k, v| "#{k}:#{v}" }
    tags.push "owner:#{repository.owner.organization? ? "organization" : "user"}"

    GitHub.dogstats.increment("repo.private_to_public", tags: tags)
    GitHub.dogstats.distribution("repo.private_to_public_health_percentage", profile.health_percentage)

    contributors = Contributors.new(repository).count
    contributor_count = contributors.computed? ? contributors.value : 0
    GitHub.dogstats.distribution("repo.private_to_public_contributors", contributor_count)

    profile
  end
end
