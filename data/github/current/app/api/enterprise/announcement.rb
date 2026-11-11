# typed: true
# frozen_string_literal: true

# Manage GHES global announcement.
class Api::Enterprise::Announcement < Api::App
  before do
    deliver_error! 404 unless GitHub.enterprise?
  end

  # Get the current announcement.
  get "/enterprise/announcement", operation_id: "enterprise-admin/get-announcement" do
    unless trusted_port?
      control_access :enterprise,
        resource: GitHub.global_business,
        allow_integrations: false,
        allow_user_via_granular_actor: false
    end

    announcement = GitHub::EnterpriseAnnouncement.get_announcement
    deliver :enterprise_announcement_hash, {
      announcement: announcement.text,
      expires_at: announcement.expires_at,
      user_dismissible: announcement.user_dismissible,
    }
  end

  # Set the current announcement.
  patch "/enterprise/announcement", operation_id: "enterprise-admin/set-announcement" do
    unless trusted_port?
      control_access :enterprise,
        resource: GitHub.global_business,
        allow_integrations: false,
        allow_user_via_granular_actor: false
    end

    data = receive_with_schema("enterprise-announcement", "set-announcement", expected_type: Hash)
    result = GitHub::EnterpriseAnnouncement.set_announcement(
      announcement: data["announcement"],
      expires_at: data["expires_at"].presence,
      user_dismissible: data["user_dismissible"],
    )
    if result.success?
      announcement = GitHub::EnterpriseAnnouncement.get_announcement
      deliver :enterprise_announcement_hash, {
        announcement: announcement.text,
        expires_at: announcement.expires_at,
        user_dismissible: announcement.user_dismissible,
      }
    else
      deliver_error!(400, message: result.errors.to_sentence)
    end
  end

  # Clear the current announcement.
  delete "/enterprise/announcement", operation_id: "enterprise-admin/remove-announcement" do
    unless trusted_port?
      control_access :enterprise,
        resource: GitHub.global_business,
        allow_integrations: false,
        allow_user_via_granular_actor: false
    end

    GitHub::EnterpriseAnnouncement.clear_announcement
    deliver_empty status: 204
  end
end
