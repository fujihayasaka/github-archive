# typed: true
# frozen_string_literal: true

# Represents an application's owner for the purpose of displaying information
# to customers. Considers runtime context (E.g. Proxima etc.) and the
# application's actual owner (E.g. a User or Organization).
class AppDisplayOwner
  include GitHub::Memoizer

  attr_accessor :actual_owner, :app

  def initialize(app:, actual_owner:)
    @app = app
    @actual_owner = actual_owner
  end

  # Public: The owner's displayable login. Considers multi-tenant mode, Proxima
  # app synchronization etc.
  #
  # Returns a String.
  memoize def display_login
    dotcom_app_owner&.display_login || actual_owner.display_login
  end

  # Public: An object that can be passed as the URL argument to the Rails
  # #link_to helper based on whether the app has been synchronized from Dotcom.
  #
  # Returns either the actual owner (User/Organization) or a String.
  memoize def url_for_link_to
    dotcom_app_owner&.url || actual_owner
  end

  # Public: either the full URL to the dotcom owner (if synchronized) or the
  # user_path of the actual user (E.g. "/monalisa")
  memoize def user_path
    return dotcom_app_owner.url if dotcom_app_owner.present?
    case actual_owner
    when User, Organization; urls.user_path(actual_owner)
    when Business; urls.enterprise_path(actual_owner.slug)
    end
  end

  memoize def avatar_url
    dotcom_app_owner&.avatar_url || actual_owner.primary_avatar_url
  end

  private

  memoize def consider_proxima?
    GitHub.multi_tenant_enterprise? && GitHub.flipper[:proxima_display_owner].enabled?
  end

  memoize def dotcom_app_owner
    if consider_proxima?
      DotcomAppOwnerMetadata.for_local_app(app)
    end
  end

  memoize def urls
    ViewModel::URLs.new
  end
end
