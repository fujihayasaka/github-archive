# typed: true
# frozen_string_literal: true

class Hook::Payload::PackageV2Payload < Hook::Payload

  def to_payload_hash
    payload = {
        action: hook_event.action,
        package: api_serialize(:registry_package_v2_hash, hook_event),
    }

    # if payload body is a symbolic link that targets to body itself, it will cause a stack level too deep error
    # and we need to remove the target from the payload from the symbolic link to avoid this error
    # https://github.com/github/github/issues/247455
    if payload[:package][:package_version][:body]&.respond_to?(:symlink_source) &&
      payload[:package][:package_version][:body].symlink_source&.instance_variable_get("@target") == payload[:package][:package_version][:body]
      payload[:package][:package_version][:body].symlink_source&.instance_variable_set("@target", nil)
    end

    payload
  end

end
