# typed: true
# frozen_string_literal: true

class RepositoryUploadsController < AbstractRepositoryController
  extend T::Sig

  include TreeHelper
  include ApplicationController::VerifiedFetchDependency
  layout "repository"
  javascript_bundle :repositories
  stylesheet_bundle :code

  before_action :ensure_valid_branch_name, only: [:index]
  before_action :login_required, only: [:show_secret_scanning_push_protection_bypass, :add_secret_scanning_push_protection_bypass]
  before_action :check_push_protection_enabled, only: [:show_secret_scanning_push_protection_bypass, :add_secret_scanning_push_protection_bypass]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  allow_verified_fetch only: [:show_secret_scanning_push_protection_bypass]

  def index
    view = Repositories::UploadView.new(
      current_user: current_user,
      branch: params[:name] || current_repository.default_branch,
      path: params[:path],
      parent_repo: current_repository,
      forked_repo: nil,
      target_branch: nil,
      quick_pull: true)

    render "repository_uploads/index", locals: { view: view, unblock_secret_success: @unblock_secret_success }
  end

  def create
    manifest = UploadManifest.where(id: params[:manifest_id], repository_id: current_repository.id).first

    if !manifest
      flash[:error] = "Add some files to include in this commit."
      return redirect_to :back
    end

    # Page reload will display push requirement message.
    if !manifest.repository&.pushable_by?(current_user)
      return redirect_to :back
    end

    return head 404 unless manifest.uploader == current_user
    return head 400 unless manifest.state_new?
    return head 400 unless manifest.complete?

    if manifest.files.empty?
      flash[:error] = "Add some files to include in this commit."
      return redirect_to :back
    end

    base_branch = params[:quick_pull]

    lfs_tracked_files = manifest.lfs_tracked_files(base_branch)
    if lfs_tracked_files.any?
      flash[:error] = "The following files are configured to be stored in Git LFS and must be pushed using the Git command line with Git LFS installed: #{lfs_tracked_files.join(", ")}"
      return redirect_to :back
    end

    manifest.update_attribute(:base_branch, base_branch) unless direct_edit?

    manifest.state_uploaded!
    manifest.schedule_commit(target_branch, commit_message, !direct_edit?)

    render "repository_uploads/processing", locals: {
      redirect_url: redirect_url(manifest),
      manifest_id: manifest.id,
      base_branch: base_branch,
      upload_directory: manifest.directory
    }
  end

  # Displays UX to allow the uploader to review a detected secret, and bypass it.
  def show_secret_scanning_push_protection_bypass # rubocop:disable GitHub/UseRestfulActions
    json_data = JSON.parse(request.body.read)

    render SecretScanning::PushProtection::FileUploadDetectedSecretsComponent.new(
      current_repository,
      SecretScanning::Util::PushProtectionFileUploads.secrets_from_json(json_data),
      params[:upload_directory],
      params[:base_branch],
      limited_user_bypass_experience_only?,
    )
  end

  # Adds bypass/allowance for a detected secret
  def add_secret_scanning_push_protection_bypass # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_user_can_write_to_repo?

    # Navigate to the file upload page if user cancels on the push protection bypass dialog
    # The path for redirection includes both the original branch and directory the user was trying to upload to
    return redirect_to repo_uploads_path(current_repository.owner_display_login, current_repository, params[:base_branch], params[:upload_directory]) if params[:cancel]

    if limited_user_bypass_experience_only?
      reason = SecretScanning::Models::BypassReason::WILL_FIX_LATER.to_s
    else
      reason = params.require(:reason)
      return head :bad_request unless reason.in?(SecretScanning::Models::BypassReason.string_values)
    end
    bypass_placeholder_ksuid = params.require(:bypass_placeholder_ksuid)

    response, error = SecretScanning::Services::PushProtectionService.promote_bypass(reason, current_repository, current_user, bypass_placeholder_ksuid)

    if response.nil? || error.present?
      flash[:error] = "An error occurred when allowing your secret. Please try again."
    else
      @unblock_secret_success = true
    end

    # Navigate to the upload page to allow the user to re-upload their files.
    # The path for redirection includes both the original branch and directory the user was trying to upload to
    redirect_to repo_uploads_path(current_repository.owner_display_login, current_repository, params[:base_branch], params[:upload_directory])
  end

  def destroy
    file = UploadManifestFile.where(id: params[:file_id], repository_id: current_repository.id).first
    return head 404 unless file
    return head 404 unless file.repository&.pushable_by?(current_user)
    return head 404 unless file.uploader == current_user
    return head 400 unless file.manifest&.state_new?
    file.cleanup!
    file.destroy
    head 200
  end

  private

  def target_branch
    params[:target_branch] || ""
  end

  def redirect_url(manifest)
    if direct_edit?
      tree_path("", target_branch, current_repository)
    else
      base = params[:quick_pull]
      range = [base, manifest.branch].compact.join("...")
      compare_path(current_repository, range, expand: true)
    end
  end

  def direct_edit?
    params["commit-choice"] == "direct"
  end

  def commit_message
    message =
      if params[:message].present?
        params[:message]
      else
        "Add files via upload"
      end

    parts = [message, params[:description]]
    parts << DcoSignoffHelper::dco_signoff_text(current_user, params) if current_repository.dco_signoff_enabled?
    parts.reject(&:blank?).join("\n\n")
  end

  def ensure_valid_branch_name
    unless current_branch_or_tag_name.present?
      flash[:error] = "Select a branch to upload files"
      redirect_to current_repository
    end
  end

  def route_supports_advisory_workspaces?
    true
  end

  def check_push_protection_enabled
    render_404 unless repo_push_protection_enabled? || user_push_protection_enabled?
  end

  sig { returns(T::Boolean) }
  def limited_user_bypass_experience_only?
    user_push_protection_enabled? && !repo_push_protection_enabled?
  end

  sig { returns(T::Boolean) }
  def repo_push_protection_enabled?
    SecretScanning::Features::Repo::PushProtection.new(current_repository).enabled?
  end

  sig { returns(T::Boolean) }
  def user_push_protection_enabled?
    SecretScanning::Features::User::PushProtection.new(current_user).enabled?
  end
end
