# typed: true
# frozen_string_literal: true

# Stafftools UI for manually recomputing oauth_enterprise_limits rows. All
# actions enqueue jobs in packages/app_security/app/jobs/oauth_enterprise_limit*;
# nothing runs the writer inline.
class Stafftools::OauthEnterpriseLimitsController < StafftoolsController
  MAX_BULK_PAIRS = 5_000
  BULK_BATCH_SIZE = 500
  FEATURE_FLAG = :stafftools_oauth_enterprise_limits_recompute

  before_action :ensure_feature_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Authnd,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    only: [:index, :business, :organization]

  def index
    render "stafftools/oauth_enterprise_limits/index", locals: { pairs: [], dry_run: true }
  end

  # GET confirmation page for recomputing oauth_enterprise_limits across an
  # entire enterprise. Not linked from anywhere else; reachable only via the
  # nested route /stafftools/enterprises/:slug/recompute_oauth_enterprise_limits.
  def business # rubocop:todo GitHub/UseRestfulActions
    business = Business.find_by(slug: params[:slug])
    return render_404 if business.nil?

    render "stafftools/oauth_enterprise_limits/business", locals: { business: business }
  end

  # GET confirmation page for recomputing oauth_enterprise_limits across all
  # members of a single organization. Reachable only via the nested route
  # /stafftools/users/:user_id/recompute_oauth_enterprise_limits_for_organization.
  def organization # rubocop:todo GitHub/UseRestfulActions
    org = Organization.find_by(login: params[:user_id])
    return render_404 if org.nil?

    render "stafftools/oauth_enterprise_limits/organization", locals: { organization: org }
  end

  def recompute_bulk # rubocop:todo GitHub/UseRestfulActions
    file = params[:file]
    if file.blank?
      flash[:error] = "Please choose a JSON file containing the pairs to recompute."
      return redirect_to stafftools_oauth_enterprise_limits_path
    end

    pairs, errors = parse_bulk_file(file)
    if errors.any?
      flash[:error] = errors.join(" ")
      return redirect_to stafftools_oauth_enterprise_limits_path
    end

    dry_run = params[:dry_run] == "1"
    instrument_recompute(scope: "bulk", payload: { count: pairs.size, dry_run: dry_run })
    GitHub.dogstats.increment("oauth_enterprise_limit.stafftools_recompute", tags: ["scope:bulk", "dry_run:#{dry_run}"])

    enqueued = 0
    unless dry_run
      pairs.each_slice(BULK_BATCH_SIZE) do |batch|
        jobs = batch.map do |pair|
          OauthEnterpriseLimitJob.new(app_id: pair["app_id"], user_id: pair["user_id"], action: "write")
        end
        ActiveJob.perform_all_later(jobs)
        enqueued += jobs.size
      end
    end

    flash.now[:notice] = if dry_run
      "Dry run: parsed #{pairs.size} valid (app_id, user_id) pairs. No jobs enqueued."
    else
      "Enqueued #{enqueued} OauthEnterpriseLimitJob(s)."
    end

    render "stafftools/oauth_enterprise_limits/index",
      locals: { pairs: pairs, dry_run: dry_run }
  end

  def recompute_pair # rubocop:todo GitHub/UseRestfulActions
    app_id = params[:id].to_i
    user_id = params[:user_id_to_recompute].to_i
    if app_id <= 0 || user_id <= 0
      flash[:error] = "app_id and user_id are required and must be positive integers."
      return redirect_to :back
    end

    instrument_recompute(scope: "pair", payload: { app_id: app_id, recompute_user_id: user_id })
    GitHub.dogstats.increment("oauth_enterprise_limit.stafftools_recompute", tags: ["scope:pair"])

    OauthEnterpriseLimitJob.perform_later(app_id: app_id, user_id: user_id, action: "write")

    flash[:notice] = "Enqueued OauthEnterpriseLimitJob for app_id=#{app_id}, user_id=#{user_id}."
    redirect_to :back
  end

  def recompute_user # rubocop:todo GitHub/UseRestfulActions
    user = User.find_by(login: params[:user_id])
    return render_404 if user.nil? || user.organization?

    instrument_recompute(scope: "user", payload: { recompute_user_id: user.id })
    GitHub.dogstats.increment("oauth_enterprise_limit.stafftools_recompute", tags: ["scope:user"])

    OauthEnterpriseLimitUpdateUserJob.perform_later(user_id: user.id)

    flash[:notice] = "Enqueued OauthEnterpriseLimitUpdateUserJob for #{user.login}."
    redirect_to stafftools_user_oauth_tokens_path(user)
  end

  def recompute_organization # rubocop:todo GitHub/UseRestfulActions
    org = Organization.find_by(login: params[:user_id])
    return render_404 if org.nil?

    instrument_recompute(scope: "organization", payload: { recompute_organization_id: org.id })
    GitHub.dogstats.increment("oauth_enterprise_limit.stafftools_recompute", tags: ["scope:organization"])

    OauthEnterpriseLimitUpdateOrganizationJob.perform_later(organization_id: org.id)

    flash[:notice] = "Enqueued OauthEnterpriseLimitUpdateOrganizationJob for #{org.login}."
    redirect_to stafftools_user_organization_limits_path(org)
  end

  def recompute_business # rubocop:todo GitHub/UseRestfulActions
    business = Business.find_by(slug: params[:slug])
    return render_404 if business.nil?

    instrument_recompute(scope: "business", payload: { recompute_business_id: business.id })
    GitHub.dogstats.increment("oauth_enterprise_limit.stafftools_recompute", tags: ["scope:business"])

    OauthEnterpriseLimitUpdateBusinessJob.perform_later(business_id: business.id)

    flash[:notice] = "Enqueued OauthEnterpriseLimitUpdateBusinessJob for #{business.slug}."
    redirect_to stafftools_enterprise_enterprise_limits_path(business)
  end

  private

  def ensure_feature_enabled
    render_404 unless FeatureFlag.vexi.enabled?(FEATURE_FLAG, default: false)
  end

  # Returns [pairs, errors]. pairs is an Array of Hashes with String keys
  # "app_id" and "user_id", both Integers.
  def parse_bulk_file(file)
    raw = file.respond_to?(:read) ? file.read : file.to_s
    parsed = JSON.parse(raw)

    return [[], ["File must contain a JSON array at the root."]] unless parsed.is_a?(Array)
    return [[], ["File contains #{parsed.size} entries which exceeds the limit of #{MAX_BULK_PAIRS}."]] if parsed.size > MAX_BULK_PAIRS

    invalid = parsed.reject do |p|
      p.is_a?(Hash) && p["app_id"].is_a?(Integer) && p["app_id"] > 0 && p["user_id"].is_a?(Integer) && p["user_id"] > 0
    end
    return [[], ["#{invalid.size} invalid entries (each entry must be {\"app_id\": Integer > 0, \"user_id\": Integer > 0})."]] if invalid.any?

    [parsed, []]
  rescue JSON::ParserError => e
    [[], ["Invalid JSON: #{e.message}"]]
  end

  def instrument_recompute(scope:, payload:)
    GitHub.instrument(
      "oauth_enterprise_limits.stafftools_recompute",
      payload.merge(
        scope: scope,
        actor: current_user,
        actor_id: current_user.id,
        actor_login: current_user.login,
      ),
    )
  end
end
