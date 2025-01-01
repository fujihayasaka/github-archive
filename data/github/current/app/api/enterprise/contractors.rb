# typed: true
# frozen_string_literal: true

class Api::Enterprise::Contractors < Api::App

  # List contractor attestations with user account.
  get "/enterprise/contractors", operation_id: :experimental do
    deliver_error! 404 unless GitHub.restrict_contractors_from_default_access_to_internal_repos?

    @route_owner = "@github/authorization"
    unless trusted_port?
      # CAP is not required because this is restricted to site admins on GHES instances
      control_access :enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false,
        disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed
    end

    per_page = per_page_from_params
    page = params.fetch(:page, 1).to_i

    ids = EnterpriseAttestation.contractor_ids(per_page: per_page, page: page)
    users = User.where(id: ids).select(:id, :login)

    results = users.map do |user|
      contractor_user_hash(user, contractor: true)
    end

    wrapped_results = WillPaginate::Collection.create(page, per_page) do |pager|
      pager.replace(results)
      pager.total_entries = ids.total_entries
    end

    deliver_raw(wrapped_results)
  end

  # Add contractor attestion for given User account.
  put "/enterprise/contractors/:user_id", operation_id: :experimental do
    deliver_error! 404 unless GitHub.restrict_contractors_from_default_access_to_internal_repos?

    @route_owner = "@github/authorization"
    unless trusted_port?
      # CAP is not required because this is restricted to site admins on GHES instances
      control_access :enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false,
        disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed
    end

    user = find_user!

    begin
      EnterpriseAttestation.set(user.id, contractor: true)
    rescue EnterpriseAttestation::ContractorsLimitExceeded => e
      deliver_error! 507, message: e.message
    end

    deliver_empty status: 204
  end

  # Remove contractor attestion for given User account.
  delete "/enterprise/contractors/:user_id", operation_id: :experimental do
    deliver_error! 404 unless GitHub.restrict_contractors_from_default_access_to_internal_repos?

    @route_owner = "@github/authorization"
    unless trusted_port?
      # CAP is not required because this is restricted to site admins on GHES instances
      control_access :enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false,
        disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed
    end

    user = find_user!

    EnterpriseAttestation.set(user.id, contractor: false)

    deliver_empty status: 204
  end

  # Get contractor attestation for given User account.
  get "/enterprise/contractors/:user_id", operation_id: :experimental do
    deliver_error! 404 unless GitHub.restrict_contractors_from_default_access_to_internal_repos?

    @route_owner = "@github/authorization"
    unless trusted_port?
      # CAP is not required because this is restricted to site admins on GHES instances
      control_access :enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false,
        disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed
    end

    user = find_user!

    contractor = EnterpriseAttestation.contractor?(user.id)
    result = contractor_user_hash(user, contractor: contractor)

    deliver_raw(result)
  end

  private

  def find_user!
    user =
      case params[:user_id]
      when /\A\d+\z/
        User.find_by(id: params[:user_id])
      else
        User.find_by(login: params[:user_id])
      end
    deliver_error!(404, {}) unless user.present?
    user
  end

  def contractor_user_hash(user, contractor:)
    # API is only used in GHES therefore safe to login use here.
    {
      id: user.id,
      login: user.login, # rubocop:disable GitHub/DoNotAllowLogin
      contractor: contractor,
    }
  end

  def per_page_from_params
    if params.key?(:per_page)
      params[:per_page].to_i
    elsif params.key?(:limit)
      params[:limit].to_i
    else
      EnterpriseAttestation::DEFAULT_PAGE_SIZE
    end
  end
end
