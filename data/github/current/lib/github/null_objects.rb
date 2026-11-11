# typed: true
# frozen_string_literal: true

class GitHub::NullObject
  def present?
    false
  end

  def !
    true
  end

  def empty?
    true
  end

  def method_missing(*args, &block)
    self
  end
end

class GitHub::NullUser < GitHub::NullObject
  def user?
    true
  end

  def ghost?
    false
  end

  def must_verify_email?
    false
  end

  def site_admin?
    false
  end
end

class GitHub::NullIssue < GitHub::NullObject
  def locked_for?(anyone)
    false
  end

  def pull_request?
    false
  end

  def over_comment_limit?
    false
  end
end

class GitHub::NullRepository < GitHub::NullObject
  def locked_on_migration?
    false
  end

  def public?
    false
  end

  def private?
    false
  end

  def archived?
    false
  end

  def owner
    nil
  end
end

class GitHub::NullDiscussion < GitHub::NullObject
end

class GitHub::NullWiki < GitHub::NullObject
  def repository
    GitHub::NullRepository.new
  end
end

class GitHub::NullPublicKey < GitHub::NullObject
  def id
    nil
  end

  def readably_by?(_)
    false
  end
end
