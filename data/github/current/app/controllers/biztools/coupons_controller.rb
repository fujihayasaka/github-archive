# typed: true
# frozen_string_literal: true

class Biztools::CouponsController < BiztoolsController
  before_action :ensure_user_exists, only: [:apply, :revoke]
  before_action \
    :ensure_coupon_exists,
    only: [:show, :destroy, :edit, :update, :report]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index, :opensource, :show, :groups]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show, :opensource, :groups],
    optional: true

  def index
    render "biztools/coupons/index"
  end

  def new
    coupon = ::Coupon.new
    coupon.group = params[:group]
    render "biztools/coupons/new", locals: { coupon: coupon, couponable_product_targets: couponable_product_targets }
  end

  def create
    result = Billing.domain.coupons.create(
      code: coupon_params[:code],
      coupon_discount_amount: coupon_params[:discount],
      coupon_group: coupon_params[:group],
      coupon_expires_at: coupon_params[:expires_at],
      coupon_note: coupon_params[:note],
      coupon_product_target: coupon_product_target,
      actor: current_user,
      redemption_limit: coupon_params[:limit].to_i,
      redemption_duration_in_days: coupon_params[:duration].to_i,
      applicable_by_staff_only: ActiveModel::Type::Boolean.new.cast(coupon_params[:staff_actor_only]) || false
    )
    case result
    when GH::Result::Error::Validation
      coupon = result.model
      flash.now[:error] = result.message
      return render "biztools/coupons/new", locals: { coupon: coupon, couponable_product_targets: couponable_product_targets }
    when GH::Result::Error
      flash[:error] = result.message
      return redirect_back(fallback_location: biztools_coupons_path)
    when GH::Result::Ok
      coupon = result.value
    end

    coupon = T.must(coupon)
    flash[:notice] = if coupon.ghec_only_group?
      "#{business_try_url(code: coupon.code)} created!"
    else
      "Coupon '#{coupon.code}' created!"
    end

    if coupon.group.present?
      redirect_to biztools_coupon_groups_path(coupon.group)
    else
      redirect_to biztools_coupons_path
    end
  end

  def destroy
    result = Billing.domain.coupons.destroy(params[:id])
    case result
    when GH::Result::Error
      flash[:error] = result.message
    when GH::Result::Ok
      flash[:notice] = "Coupon destroyed!"
    end

    respond_to do |format|
      format.json { render json: {} }
      format.html { redirect_to biztools_coupons_path }
    end
  end

  def groups # rubocop:todo GitHub/UseRestfulActions
    @coupons  = list_coupons(params[:group], current_page, params[:state], params[:sort])
    @counters = counters(params[:group])
    @state    = params[:state] || "active"
    render "biztools/coupons/groups"
  end

  def search # rubocop:todo GitHub/UseRestfulActions
    if this_coupon
      redirect_to biztools_coupon_path(this_coupon)
    else
      flash[:error] = "Couldn’t find the coupon."
      redirect_to :back
    end
  end

  def show
    state = params[:state] || "active"
    coupon_redemptions = this_coupon
      .coupon_redemptions
      .includes(:billable_entity)
      .where(expired: (state == "expired"))
      .paginate(page: current_page)

    coupon = T.must(Billing.domain.coupons.by_code(this_coupon.code))

    render "biztools/coupons/show", locals: {
      view: Biztools::Coupon::ShowView.new(coupon, state: state),
      coupon: coupon,
      coupon_redemptions: coupon_redemptions,
    }
  end

  def edit
    render "biztools/coupons/edit", locals: { coupon: this_coupon }
  end

  def update
    if this_coupon.update(coupon_params)
      redirect_to biztools_coupon_path(this_coupon)
    else
      flash.now[:error] = this_coupon.errors.full_messages.to_sentence
      edit
    end
  end

  # Applies a coupon directly onto a user
  def apply # rubocop:todo GitHub/UseRestfulActions
    if couponable_entity.has_commercial_interaction_restriction?
      flash[:error] = "Account SDN status is: '#{couponable_entity.trade_screening_status}'. Cannot apply coupon to an account with commercial interaction restriction. "
    else
      couponable_entity.update_attribute(:billing_type, "card") if !couponable_entity.business? && couponable_entity.gift?

      redemption = couponable_entity.redeem_coupon(params[:code],
        allow_reuse: true, actor: current_user)
      if redemption
        flash[:notice] = "Coupon '#{params[:code]}' applied"
      else
        errors = couponable_entity.errors.full_messages.to_sentence.dup
        if couponable_entity.coupon_redemptions.active.any?
          errors << " That account already has a coupon applied: #{biztools_coupon_url(couponable_entity.coupon_redemptions.active.first.coupon)}"
        elsif couponable_entity.business? && couponable_entity.metered_plan?
          errors << " Coupon cannot be applied to metered enterprise accounts."
        elsif couponable_entity.business? && couponable_entity.trial? && !couponable_entity.has_valid_payment_method?
          errors << " Enterprise accounts on a trial require a payment method to apply a coupon as this process will complete and convert the trial."
        end
        flash[:error] = errors
      end
    end
    redirect_to :back
  end

  # Removes a user's active coupon
  def revoke # rubocop:todo GitHub/UseRestfulActions
    couponable_entity.expire_active_coupon
    redirect_to :back
  end

  def report # rubocop:todo GitHub/UseRestfulActions
    filename = "coupon-redemptions-#{this_coupon}-#{Date.today}.csv"
    send_data \
      Biztools::CouponReport.new(this_coupon).generate,
      type: "text/csv",
      disposition: "attachment;filename=#{filename}"
  end

  def opensource # rubocop:todo GitHub/UseRestfulActions
    @user = User.find_by_login params[:user_id]
    return render_404 if @user.nil?

    GitHub.dogstats.time("github.biztools.coupons.repos_count_time", tags: ["type:popular"]) do
      @popular_repository = @user.repositories
                                .where(public: true)
                                .where("pushed_at > #{1.year.ago.to_i}")
                                .joins(:repository_license)
                                .find do |repo|
        next true if repo.stargazer_count > 100
        next true if repo.public_fork_count > 100
        repo.watchers.count > 100
      end
    end

    @public_repos_committers = 0
    @public_repos_commits = 0
    @private_repos_committers = 0
    @private_repos_commits = 0

    GitHub.dogstats.time("github.biztools.coupons.committers_count_and_commit_count_time") do
      user_repos = @user.repositories.preload(:commit_contributions)
      public_repos = user_repos.where(public: true)
      @public_repos_count = public_repos.count
      @public_repos_committers = public_repos.flat_map { |repo| CommitContributions.domain.contributed_user_ids(repository: repo) }.uniq.count
      @public_repos_commits = public_repos.map { |repo| CommitContributions.domain.commit_count_for_repository(repo) }.sum
      private_repos = user_repos.where(public: false)
      @private_repos_count = private_repos.count
      @private_repos_committers = private_repos.flat_map { |repo| CommitContributions.domain.contributed_user_ids(repository: repo) }.uniq.count
      @private_repos_commits = private_repos.map { |repo| CommitContributions.domain.commit_count_for_repository(repo) }.sum
    end

    render "biztools/coupons/opensource"
  end

  private

  memoize def couponable_product_targets
    if current_user.feature_flag_enabled?(:coupon_product_targets, default: false)
      Billing::ProductUUID.couponable.select(:product_type, :product_key, :name).distinct.to_a
    else
      []
    end
  end

  sig { returns(T.nilable(Billing::Public::Product::ProductIdentifier)) }
  memoize def coupon_product_target
    return nil unless params["coupon_product_target"].present?

    product_type, product_key = JSON.parse(params["coupon_product_target"])
    Billing::Public::Product::ProductIdentifier.new(product_type: product_type, product_key: product_key)
  end

  def couponable_entity
    current_account || current_business
  end

  def this_coupon # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @coupon ||= ::Coupon.find_by_code(params[:id])
  end
  helper_method :this_coupon

  def ensure_coupon_exists
    render_404 if this_coupon.nil?
  end

  def list_coupons(group, page, state = :active, order = :active_first)
    if order.try(:to_sym) == :alphabetical
      order_condition = "code ASC"
    else
      order_condition = "expires_at DESC"
    end

    coupons = state.try(:to_sym) == :expired ? ::Coupon.expired : ::Coupon.active
    coupons.for_group(group).order(order_condition).page(page)
  end

  def counters(group)
    {
      active: ::Coupon.for_group(group).active.count,
      expired: ::Coupon.for_group(group).expired.count,
    }
  end

  def coupon_params
    params.require(:coupon).permit(*exposed_attributes)
  end

  def exposed_attributes
    [:code, :plan, :discount, :duration, :limit, :group,
      :expires_at, :note, :staff_actor_only]
  end
end
