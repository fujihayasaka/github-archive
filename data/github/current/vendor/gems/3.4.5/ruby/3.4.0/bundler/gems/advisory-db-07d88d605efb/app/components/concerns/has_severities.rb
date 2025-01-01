# frozen_string_literal: true

module HasSeverities
  def severities
    AdvisoryDB.severities
  end

  def severity_label(severity)
    AdvisoryDB.severity_label(severity)
  end

  def severity_color(severity)
    AdvisoryDB.severity_color(severity)
  end

  def severity_scheme(severity)
    AdvisoryDB.severity_scheme(severity)
  end
end
