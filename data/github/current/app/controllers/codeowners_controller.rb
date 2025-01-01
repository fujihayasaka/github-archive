# typed: true
# frozen_string_literal: true

class CodeownersController < GitContentController
  before_action :require_blob

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:validity]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    ref_name = current_repository.heads.exist?(tree_name) ? tree_name : current_repository.default_branch

    codeowners = Repository::Codeowners.new(current_repository, ref: ref_name, paths: [path_string])

    respond_to do |format|
      format.html do
        render partial: "codeowners/codeowners", locals: { codeowners: codeowners, path: path_string }
      end
    end
  end

  def validity # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render Blobs::CodeownersErrorsComponent.new(current_blob), layout: false
      end
      format.json do
        owner_resolver = Repository::Codeowners::ActiveRecordOwnerResolver.new(current_repository)

        codeowners_file = ::Codeowners::File.new(current_blob.data.to_s, owner_resolver: owner_resolver)

        codeowners_errors = (codeowners_file.errors + codeowners_file.owner_errors).sort_by(&:line)

        render json: codeowners_errors
      end
    end
  end

  private

  def require_blob
    return render_404 if path_string.blank? || current_commit.nil?
    render_404 unless current_blob
  end

  memoize def current_blob
    current_repository.blob(tree_sha, path_string)
  end
end
