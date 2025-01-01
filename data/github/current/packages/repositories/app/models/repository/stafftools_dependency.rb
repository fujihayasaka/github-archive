# typed: false
# frozen_string_literal: true

module Repository::StafftoolsDependency
  # Public: Request staff access to a private repository.
  #
  # A User object of the staffer requesting access must be passed in. A newly created
  # StaffAccessRequest object will be returned if successful.
  #
  # This does not create an actual access grant, nor an unlock — it only generates
  # the StaffAccessRequest.
  #
  # Returns a StaffAccessRequest.
  def request_staff_access(staffer, reason)
    self.staff_access_requests.create(requested_by: staffer, reason: reason)
  end
end
