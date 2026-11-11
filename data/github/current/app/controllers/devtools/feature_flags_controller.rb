# rubocop:disable GitHub/FeatureManagement/NoVexiManagementUsage
# typed: strict
# frozen_string_literal: true

class Devtools::FeatureFlagsController < DevtoolsController
  include GitHub::Memoizer

  skip_before_action :cap_pagination, unless: :robot?, only: :show

  javascript_bundle "feature-flags"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:add_actor]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:check_actor]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:remove_actor]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:user_autocomplete]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show, :new, :remove_actor, :add_actor,
      :check_actor],
    optional: true

  FEATURES_PER_PAGE = 25
  ACTORS_PER_PAGE = 50
  MAXIMUM_USERS_ADDED_AT_ONCE = 50
  GITHUB_ORG_ID = 9919

  sig { void }
  def index
    name_filter = parsed_query.query.presence

    result = fm_lite_client.list_feature_flags(
      page: current_page,
      page_size: FEATURES_PER_PAGE,
      name_filter: name_filter,
      order_by: parsed_query.sort
    )
    raw_features = result[:features]
    total_count = result[:total_count]

    feature_view_models = raw_features.map { |feature| FeatureManagement::Models::DevtoolsFeature.new(feature) }
    features = FeatureManagement::Models::PaginatedDevtoolsFeaturesCollection.new(
      feature_view_models,
      page: current_page,
      per_page: FEATURES_PER_PAGE,
      total_entries: total_count
    )

    render "devtools/feature_flags/index", locals: {
      features: features,
      q: params[:q],
    }
  end

  sig { void }
  def user_autocomplete # rubocop:todo GitHub/UseRestfulActions
    users = User.search(params[:q], with_orgs: true)

    render "devtools/feature_flags/user_autocomplete", formats: :html, layout: false, locals: { users: users }
  end

  sig { void }
  def show
    feature_name = params[:id]
    feature = fm_lite_client.get_feature_flag(feature_name)
    if feature.nil?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end
    feature_flag = FeatureManagement::Models::DevtoolsFeature.new(feature)

    actor_type_filter = params[:actor_type]
    filtered_actors = feature_flag.filtered_actors(actor_type_filter)
    show_big_feature_actors = true
    if filtered_actors.length > ACTORS_PER_PAGE
      show_big_feature_actors = params[:show_big_feature_actors].nil? ? false : true
    end

    actors = nil
    if show_big_feature_actors
      actors = FeatureManagement::Models::PaginatedDevtoolsActorsCollection.new(
        filtered_actors,
        page: current_page,
        per_page: ACTORS_PER_PAGE,
      )
    end

    render "devtools/feature_flags/show", locals: {
      feature_flag: feature_flag,
      actors: actors,
      show_big_feature_actors: show_big_feature_actors,
      selected_actor_filter: actor_type_filter,
      celebrate: flash[:celebrate],
    }
  rescue StandardError => e
    flash.now[:error] = e.message
    redirect_to devtools_feature_flags_path
  end

  sig { void }
  def new
    render "devtools/feature_flags/new", locals: { errors: {} }
  end

  sig { void }
  def create
    feature_name = params[:name].presence
    if feature_name.blank?
      flash.now[:error] = "Error creating the feature"
      render "devtools/feature_flags/new", locals: { errors: { name: "name cannot be blank" } }
      return
    end
    if feature_name.length > 200
      flash.now[:error] = "Error creating the feature"
      render "devtools/feature_flags/new", locals: { errors: { name: "name must be less than or equal to 200 characters" } }
      return
    end

    if params[:enable] == "true"
      FeatureFlag.vexi_management.enable_feature_flag(feature_name)
    else
      FeatureFlag.vexi_management.disable_feature_flag(feature_name)
    end

    redirect_to devtools_feature_flag_path(feature_name), notice: "'#{feature_name}' has been created"
  rescue StandardError => e
    flash.now[:error] = e.message
    render "devtools/feature_flags/new", locals: { errors: {} }
  end

  sig { void }
  def destroy
    feature_name = get_feature_name_from_params

    fm_lite_client.delete_feature_flag(feature_name)

    redirect_to devtools_feature_flags_path, notice: "'#{feature_name}' has been deleted and disabled."
  rescue StandardError => e
    flash.now[:error] = e.message
    redirect_to devtools_feature_flag_path(feature_name)
  end

  sig { void }
  def enable # rubocop:todo GitHub/UseRestfulActions
    feature_name = get_feature_name_from_params
    if feature_name.blank?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end

    FeatureFlag.vexi_management.enable_feature_flag(feature_name)

    redirect_to devtools_feature_flag_path(feature_name), flash: {
      notice: "Enabled '#{feature_name}' for everyone.",
      celebrate: true
    }
  rescue StandardError => e
    flash.now[:error] = e.message
    redirect_to devtools_feature_flag_path(feature_name)
  end

  sig { void }
  def disable # rubocop:todo GitHub/UseRestfulActions
    feature_name = get_feature_name_from_params
    if feature_name.blank?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end

    FeatureFlag.vexi_management.disable_feature_flag(feature_name)

    redirect_to devtools_feature_flag_path(feature_name), flash: {
      notice: "Disabled '#{feature_name}' for everyone.",
    }
  rescue StandardError => e
    flash.now[:error] = e.message
    redirect_to devtools_feature_flag_path(feature_name)
  end

  sig { void }
  def update_percentage_of_actors # rubocop:todo GitHub/UseRestfulActions
    feature_name = get_feature_name_from_params
    if feature_name.blank?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end
    percentage = params[:percentage_of_actors].to_f

    FeatureFlag.vexi_management.set_feature_flag_percentage_of_actors(feature_name, percentage)

    redirect_to devtools_feature_flag_path(feature_name), notice: "Enabled '#{feature_name}' #{percentage}% of the actors."
  rescue StandardError => e
    flash.now[:error] = e.message
    redirect_to devtools_feature_flag_path(feature_name)
  end

  sig { void }
  def update_percentage_of_calls # rubocop:todo GitHub/UseRestfulActions
    feature_name = get_feature_name_from_params
    if feature_name.blank?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end
    percentage = params[:percentage_of_calls].to_f

    FeatureFlag.vexi_management.set_feature_flag_percentage_of_calls(feature_name, percentage)

    redirect_to devtools_feature_flag_path(feature_name), notice: "Enabled '#{feature_name}' #{percentage}% of the time."
  rescue StandardError => e
    flash.now[:error] = e.message
    redirect_to devtools_feature_flag_path(feature_name)
  end

  sig { void }
  def add_actor # rubocop:todo GitHub/UseRestfulActions
    feature_name = get_feature_name_from_params
    feature = fm_lite_client.get_feature_flag(feature_name)
    if feature.nil?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end
    feature_flag = FeatureManagement::Models::DevtoolsFeature.new(feature)

    render "devtools/feature_flags/add_actor", locals: { feature: feature_flag }
  rescue StandardError => e
    flash.now[:error] = e.message
    redirect_to devtools_feature_flag_path(feature_name)
  end

  sig { void }
  def remove_actor # rubocop:todo GitHub/UseRestfulActions
    feature_name = get_feature_name_from_params
    feature = fm_lite_client.get_feature_flag(feature_name)
    if feature.nil?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end
    feature_flag = FeatureManagement::Models::DevtoolsFeature.new(feature)

    render "devtools/feature_flags/remove_actor", locals: { feature: feature_flag }
  rescue StandardError => e
    flash.now[:error] = e.message
    redirect_to devtools_feature_flag_path(feature_name)
  end

  sig { void }
  def check_actor # rubocop:todo GitHub/UseRestfulActions
    feature_name = get_feature_name_from_params
    feature = fm_lite_client.get_feature_flag(feature_name)
    if feature.nil?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end
    feature_flag = FeatureManagement::Models::DevtoolsFeature.new(feature)

    render "devtools/feature_flags/check_actor", locals: { feature: feature_flag }
  rescue StandardError => e
    flash.now[:error] = e.message
    redirect_to devtools_feature_flag_path(feature_name)
  end

  sig { void }
  def activate_actor # rubocop:todo GitHub/UseRestfulActions
    feature_name = get_feature_name_from_params
    feature = fm_lite_client.get_feature_flag(feature_name)
    if feature.nil?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end
    feature_flag = FeatureManagement::Models::DevtoolsFeature.new(feature)
    actors = actors_from_params

    FeatureFlag.vexi_management.add_feature_flag_actors(feature_name, actors.found.map(&:vexi_id))
    params[:users] = actors.users_not_found
    params[:repos] = actors.repos_not_found

    if actors.errors.empty?
      redirect_to devtools_feature_flag_path(feature_name), notice: "'#{feature_name}' has been updated."
    else
      flash[:error] = actors.errors.join(" ")
      render "devtools/feature_flags/add_actor", locals: { feature: feature_flag }
    end
  rescue StandardError => e
    flash[:error] = e.message
    redirect_to devtools_feature_flag_path(feature_name)
  end

  sig { void }
  def deactivate_actor # rubocop:todo GitHub/UseRestfulActions
    feature_name = get_feature_name_from_params
    feature = fm_lite_client.get_feature_flag(feature_name)
    if feature.nil?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end
    feature_flag = FeatureManagement::Models::DevtoolsFeature.new(feature)
    actors = actors_from_params

    FeatureFlag.vexi_management.remove_feature_flag_actors(feature_name, actors.found.map(&:vexi_id))
    params[:users] = actors.users_not_found
    params[:repos] = actors.repos_not_found

    if actors.errors.empty?
      redirect_to devtools_feature_flag_path(feature_name), notice: "'#{feature_name}' has been updated."
    else
      flash[:error] = actors.errors.join(" ")
      render "devtools/feature_flags/remove_actor", locals: { feature: feature_flag }
    end
  rescue StandardError => e
    flash[:error] = e.message
    redirect_to devtools_feature_flag_path(feature_name)
  end

  sig { void }
  def verify_actor # rubocop:todo GitHub/UseRestfulActions
    feature_name = get_feature_name_from_params
    feature = FeatureFlag.vexi_management.get_feature_flag(feature_name)
    if feature.nil?
      flash[:error] = "Feature flag doesn't exist."
      render "devtools/feature_flags/check_actor", locals: { feature: feature }
      return
    end
    actors = actors_from_params

    if actors.errors.empty?
      actor_statuses = actors.found.map do |actor|
        if feature.actors.include?([actor.vexi_id, true])
          "#{actor.name} is added to this flag."
        else
          "#{actor.name} is not added to this flag."
        end
      end
      flash[:notice] = actor_statuses.join(" ")
    else
      flash[:error] = actors.errors.join(" ")
    end

    render "devtools/feature_flags/check_actor", locals: { feature: feature }
  rescue StandardError => e
    flash.now[:error] = e.message
    render "devtools/feature_flags/check_actor", locals: { feature: feature }
  end

  sig { void }
  def activate_custom_gate # rubocop:todo GitHub/UseRestfulActions
    feature_name = get_feature_name_from_params
    if feature_name.blank?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end
    custom_gate = params[:custom_gate]

    FeatureFlag.vexi_management.add_feature_flag_custom_gate(feature_name, custom_gate)

    redirect_to devtools_feature_flag_path(feature_name), \
      notice: "Enabled '#{feature_name}' for the '#{custom_gate}' group."
  rescue StandardError => e
    redirect_to devtools_feature_flag_path(feature_name)
  end

  sig { void }
  def deactivate_custom_gate # rubocop:todo GitHub/UseRestfulActions
    feature_name = get_feature_name_from_params
    if feature_name.blank?
      redirect_back fallback_location: devtools_feature_flags_path, flash: { error: "Feature flag doesn't exist." }
      return
    end
    custom_gate = params[:custom_gate]

    FeatureFlag.vexi_management.remove_feature_flag_custom_gate(feature_name, custom_gate)

    redirect_to devtools_feature_flag_path(feature_name), \
      notice: "Removed the '#{custom_gate}' group from '#{feature_name}'."
  rescue StandardError => e
    redirect_to devtools_feature_flag_path(feature_name)
  end

  sig { void }
  private def set_default_nav_breadcrumb
    return unless header_redesign_enabled?

    feature_name = get_feature_name_from_params
    feature = nil
    if feature_name.present?
      feature = FeatureFlag.vexi_management.get_feature_flag(feature_name)
    end

    if feature
      set_nav_breadcrumb ContextRegion::Devtools::FeatureFlagCrumb.new(feature)
    else
      set_nav_breadcrumb ContextRegion::Devtools::FeatureFlagsIndexCrumb.new
    end
  end

  sig { returns(FeatureFlag::Query) }
  memoize private def parsed_query
    FeatureFlag::Query.new(query: params[:q], current_user: current_user)
  end

  class Actor < T::Struct
    const :name, String
    const :object, Vexi::Actor

    delegate :vexi_id, to: :object
  end

  class ActorsFromParams < T::Struct
    const :found, T::Array[Actor]
    const :users_not_found, T::Array[String]
    const :repos_not_found, T::Array[String]
    const :errors, T::Array[String]
  end

  sig { returns(ActorsFromParams) }
  private def actors_from_params
    actors = T.let([], T::Array[Actor])
    users_not_found = []
    repos_not_found = []
    errors = []

    if params[:enterprise].present?
      if business = Business.find_by(slug: params[:enterprise].strip)
        actors << Actor.new(
          object: business,
          name: params[:enterprise],
        )
      else
        errors << "Enterprise #{params[:enterprise]} not found."
      end
    end

    params[:users] = params[:users]&.filter(&:present?)
    if params[:users].present?
      user_names = params[:users]
      if user_names.size > MAXIMUM_USERS_ADDED_AT_ONCE
        users_not_found += user_names
        errors << "The maximum number of users allowed to be added or removed at once is #{MAXIMUM_USERS_ADDED_AT_ONCE}"
      else
        # Get User active records then using index_by to turn the list into a hash where the key is the User's name.
        # Using hash#slice returns a hash containing the removed key/value pairs in the same order as the slice's parameters.
        users = User.with_logins(user_names).index_by { |user| "#{user.name.downcase}" }

        user_names.each do |name|
          if users.has_key?(name.downcase)
            actors << Actor.new(object: users[name], name:)
          else
            users_not_found << name
          end
        end

        if users_not_found.present?
          errors << "#{"User".pluralize(users_not_found.size)} #{users_not_found.to_sentence} not found."
        end
      end
    end

    params[:repos] = params[:repos]&.filter(&:present?)
    if params[:repos].present?
      repo_names_with_owners = params[:repos]
      if repo_names_with_owners.size > MAXIMUM_USERS_ADDED_AT_ONCE
        repos_not_found += repo_names_with_owners
        errors << "The maximum number of repos allowed to be added or removed at once is #{MAXIMUM_USERS_ADDED_AT_ONCE}"
      else
        repos = Repository.with_names_with_owners(repo_names_with_owners).index_by { |repo| repo.nwo.downcase }

        repo_names_with_owners.each do |nwo|
          if repos.has_key?(nwo.downcase)
            actors << Actor.new(object: repos[nwo], name: nwo)
          else
            repos_not_found << nwo
          end
        end

        if repos_not_found.present?
          errors << "#{"Repository".pluralize(repos_not_found.size)} #{repos_not_found.to_sentence} not found."
        end
      end
    end

    if params[:oauth_application].present?
      if oauth_application = OauthAccessTokens.domain.oauth_applications.by_key(params[:oauth_application].strip)
        actors << Actor.new(object: oauth_application, name: params[:oauth_application])
      else
        errors << "OauthApplication #{params[:oauth_application]} not found."
      end
    end

    if params[:integration].present?
      if integration = Integration.find_by(id: params[:integration].strip)
        actors << Actor.new(object: integration, name: params[:integration])
      else
        errors << "Integration #{params[:integration]} not found."
      end
    end

    if params[:vulnerability].present?
      # Intentionally unscoped — devtools should find advisories of any scope
      if vulnerability = Vulnerability.find_by(ghsa_id: params[:vulnerability].strip)
        actors << Actor.new(object: vulnerability, name: params[:vulnerability])
      else
        errors << "Security advisory #{params[:vulnerability]} not found."
      end
    end

    if params[:host].present?
      actors << Actor.new(
        object: GitHub::FlipperHost.new(params[:host].strip),
        name: params[:host],
      )
    end

    if params[:site].present?
      actors << Actor.new(
        object: GitHub::FlipperSite.new(params[:site].strip),
        name: params[:site],
      )
    end

    if params[:role].present?
      actors << Actor.new(
        object: GitHub::FlipperRole.new(params[:role].strip),
        name: params[:role],
      )
    end

    if params[:vexi_id].present?
      vexi_id = params[:vexi_id].strip

      if record = GitHub::VexiActor.from_vexi_id(vexi_id)
        actors << Actor.new(
          object: record,
          name: params[:vexi_id],
        )
      else
        errors << "VexiActor #{params[:vexi_id]} not found."
      end
    end

    ActorsFromParams.new(found: actors, users_not_found:, repos_not_found:, errors:)
  end

  sig { returns(String) }
  private def get_feature_name_from_params
    params[:feature_flag_id] || params[:id] || ""
  end

  sig { returns(FeatureManagement::FeatureManagementLiteClient) }
  memoize private def fm_lite_client
    FeatureManagement::FeatureManagementLiteClient.new(timeout: 3.0, open_timeout: 2.0, max_retries: 2)
  end
end

# rubocop:enable GitHub/FeatureManagement/NoVexiManagementUsage
