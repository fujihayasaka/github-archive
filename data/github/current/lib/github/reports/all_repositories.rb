# typed: true
# frozen_string_literal: true

module GitHub
  module Reports
    class AllRepositories
      def data
        header = %w(created_at owner_id owner_type owner_name id name visibility readable_size raw_size
                    collaborators fork? deleted?)
        header << "anonymous_access_enabled?" if GitHub.anonymous_git_access_enabled?

        CSV.generate do |csv|
          csv << header
          anonymous_git_access_repo_ids = Repository.with_anonymous_git_access.pluck(:id).to_set
          Repository.find_each do |r|
            owner = r.owner
            row = [r.created_at, r.owner_id, (owner ? owner.type : "N/A"),
                   (owner ? owner.login : "N/A"), r.id, r.name,
                   r.visibility, r.human_disk_usage, r.disk_usage, r.members_count, r.fork?, !r.active?]
            row << anonymous_git_access_repo_ids.include?(r.id) if GitHub.anonymous_git_access_enabled?
            csv << row
          end
        end
      end
    end
  end
end
