# typed: true
# frozen_string_literal: true

# This class is exclusively used as a notifications/newsies thread key from
# within a VulnerabilityAlertingEvent::VulnerableRepositoryNotification.
class RepositoryDependabotAlertsThread
  include GitHub::Relay::GlobalIdentification
  include GlobalID::Identification

  # Needed by GlobalID::Identification
  def self.find(repo_id)
    find_by_id(repo_id)
  end

  def self.find_by_id(repo_id)  # rubocop:disable GitHub/FindByDef
    return unless repository = Repository.find_by(id: repo_id)
    new(repository)
  end

  attr_accessor :repository

  def initialize(repository)
    @repository = repository
  end

  def id
    repository.id
  end

  def notifications_author
    return @notifications_author if defined? @notifications_author
    @notifications_author = User.find_by(login: GitHub.trusted_oauth_apps_org_name)
  end

  def notifications_list
    repository
  end

  def notifications_thread
    self
  end

  def notifications_permalink
    UrlHelpers.repository_alerts_url(host: GitHub.url, repository: repository, user_id: repository.owner)
  end

  # since repository is required to instantiate the object, this can seem
  # redundant – but this method is necessary because within GQL, we implement
  # an `async_api_can_access` method which calls Permission#async_repo_and_org_owner
  # which in turn expects to see an `async_repository` method.
  def async_repository
    Promise.resolve(repository)
  end

  def async_readable_by?(actor)
    # preload async_configuration_owner because owner is synchrounously
    # accessed deep down the call stack of vulnerability_alerts_visible_to
    repository.async_configuration_owner.then do
      repository.vulnerability_alerts_visible_to?(actor)
    end
  end

  def readable_by?(actor)
    async_readable_by?(actor).sync
  end
end
