# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

class BranchProtector
  class BranchProtectionResult
    attr_reader :protected_branch, :errors
    def initialize(protected_branch: nil, errors: nil)
      @protected_branch = protected_branch
      @errors = errors
    end

    def success?
      @errors.nil?
    end
  end

  # When a user tries to create a protected branch with contexts that are duplicated, we raise this error
  class DuplicatedContextError < StandardError ; end

  def self.extract_required_status_checks(repo, data)
    return if data.nil?

    result = data.slice("strict", "contexts", "checks", "include_admins").deep_symbolize_keys!

    if result[:checks]
      integration_ids = result[:checks].map { |check| check[:app_id] }
      integrations = Integration.where(id: integration_ids).index_by(&:id)
      result[:checks] = result[:checks].map do |check|
        if check[:app_id] == -1
          { context: check[:context], source: :any }
        else
          { context: check[:context], source: :app, integration: integrations[check[:app_id]] }
        end
      end

      if result[:checks].pluck(:context).uniq.length != result[:checks].length
        raise DuplicatedContextError.new("Context must be unique per branch protection.")
      end
    end
    result
  end

  def initialize(repository:, actor:, ref_name:, data:, include_required_signatures:, entry_point: nil)
    @repository = repository
    @actor = actor
    @ref_name = ref_name
    @data = data
    @include_required_signatures = include_required_signatures
    @entry_point = entry_point
  end

  def protect_branch
    begin
      protected_branch_params = {
        creator: @actor,
        required_status_checks: self.class.extract_required_status_checks(
          @repository,
          @data["required_status_checks"],
        ),
        required_pull_request_reviews: extract_required_pull_request_reviews,
        required_signatures: extract_required_signatures,
        enforce_admins: @data["enforce_admins"],
        restrictions: extract_restrictions,
      }

      protected_branch_params[:required_linear_history] = @data["required_linear_history"]
      protected_branch_params[:block_force_pushes] = !@data["allow_force_pushes"]
      protected_branch_params[:block_deletions] = !@data["allow_deletions"]
      protected_branch_params[:create_protected] = @data["block_creations"]
      protected_branch_params[:required_conversation_resolution] = @data["required_conversation_resolution"]
      protected_branch_params[:lock_branch] = @data["lock_branch"]
      protected_branch_params[:lock_allows_fetch_and_merge] = @data["allow_fork_syncing"]
      protected_branch_params[:entry_point] = @entry_point

      protected_branch = @repository.protect_branch(@ref_name, **protected_branch_params)
      BranchProtectionResult.new(protected_branch: protected_branch)
    rescue ProtectedBranch::OnlyOrgsHaveAuthorizedActors
      BranchProtectionResult.new(errors: ["Only organization repositories can have users and team restrictions"])
    rescue ProtectedBranch::TooManyPermittedActors => e
      BranchProtectionResult.new(errors: [e.message])
    rescue ActiveRecord::RecordInvalid => e
      BranchProtectionResult.new(errors: e.record.errors)
    rescue DuplicatedContextError => e
      BranchProtectionResult.new(errors: [e.message])
    end
  end

  private

  def extract_required_pull_request_reviews
    return if @data["required_pull_request_reviews"].nil?

    object = @data["required_pull_request_reviews"]

    keys = %w[
      dismissal_restrictions
      dismiss_stale_reviews
      require_code_owner_reviews
      required_approving_review_count
      bypass_pull_request_allowances
      require_last_push_approval
    ]

    object.slice(*keys).symbolize_keys!
  end

  def extract_restrictions
    restrictions = @data["restrictions"]
    return if restrictions.nil?

    {
      users: restrictions["users"],
      teams: restrictions["teams"],
      integrations: restrictions["apps"],
    }
  end

  def extract_required_signatures
    @data["required_signatures"] if @include_required_signatures
  end
end
