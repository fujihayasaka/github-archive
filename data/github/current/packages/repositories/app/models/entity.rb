# typed: false
# frozen_string_literal: true

# Required contract for any Entity
module Entity
  class NotImplemented < RuntimeError; end

  # Public: Return the name of this entity anlong with owner
  def name_with_owner
    raise NotImplemented
  end

  # Public: Is this entity readable by the User?
  def readable_by?(user)
    raise NotImplemented
  end

  # Public: Is this entity writable by by the User?
  def writable_by?(user)
    raise NotImplemented
  end

  # Public: is this entity accessible to the whole world?
  def public?
    raise NotImplemented
  end

  # Public: is this entity only accessible to associated owners / collaborators?
  def private?
    raise NotImplemented
  end

  # Public: Return the nice human name of this class
  def human_name
    self.class.name.titleize.downcase
  end
end
