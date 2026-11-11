# typed: true
# frozen_string_literal: true

class Copilot::Chat::FileContentsController < Copilot::Chat::AbstractChatController
  before_action :require_repository
  before_action :require_file_path

  depends_on_clusters(
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    only: [:show],
  )

  def show
    result = fetch_file_content

    if result
      render json: {
        content: result[:content],
        language: result[:language]
      }
    else
      render_404
    end
  end

  private

  memoize def current_repository
    if params[:owner_login].present? && params[:name].present?
      Repository.find_by(owner_login: params[:owner_login], name: params[:name])
    else
      Repositories.domain.by_id(params[:id].to_i)
    end
  end

  def require_repository
    render_404 unless current_repository
  end

  def require_file_path
    render_404 unless file_path.present?
  end

  def git_ref
    # Use ref from URL path, fallback to default branch if not provided
    ref = params[:ref] || current_repository.default_branch
    # Fallback to HEAD if no default branch is set
    ref.present? ? ref : "HEAD"
  end

  def file_path
    # Handle file_path from URL path (comes as array from splat parameter)
    if params[:file_path].is_a?(Array)
      params[:file_path].join("/")
    else
      params[:file_path]
    end
  end

  def fetch_file_content
    begin
      # Resolve the ref (branch name) to an OID (commit SHA)
      ref = git_ref
      path = file_path
      Rails.logger.debug("Fetching file content for #{path} at ref #{ref}")

      # Get the commit OID for the ref
      commit_oid = resolve_ref_to_oid(ref)
      return nil unless commit_oid

      Rails.logger.debug("Resolved ref #{ref} to OID #{commit_oid}")
      blob = current_repository.blob(commit_oid, path, blob_limits)

      return nil unless blob

      # Return both content and language information
      content = if blob.text?
        blob.data
      else
        "[Binary file - content not displayed]"
      end

      {
        content: content,
        language: blob.language&.name
      }
    rescue => e
      Rails.logger.warn("Failed to fetch file content: #{e.message}")
      nil
    end
  end

  def resolve_ref_to_oid(ref)
    # Try to resolve the ref to a commit OID
    begin
      # Check if it's already an OID (SHA-1: 40-character hex string, SHA-256: 64-character hex string)
      return ref if ref.match?(/\A[0-9a-f]{40}\z/i) || ref.match?(/\A[0-9a-f]{64}\z/i)

      # Try to resolve as a branch reference
      branch_ref = current_repository.heads.find(ref)
      return branch_ref.target_oid if branch_ref

      # Try to resolve as a tag reference
      tag_ref = current_repository.tags.find(ref)
      return tag_ref.target_oid if tag_ref

      nil
    rescue => e
      Rails.logger.warn("Failed to resolve ref #{ref}: #{e.message}")
      nil
    end
  end

  def blob_limits
    { truncate: false, limit: 1.megabyte }
  end

  # CAP is not bypassed here as repo is required by :require_repository
  def resource_for_conditional_access
    return current_repository if current_repository
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  # CAP is not bypassed here as AbstractChatController requires a logged in user
  def target_for_conditional_access
    return current_repository.owner if current_repository
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
