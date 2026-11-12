# frozen_string_literal: true

# Module for shared data, shared logic belongs in concerns
module AdvisoryReviews
  SOURCES = {
    "repository_advisories" => {
      label: "GitHub Security Advisory",
      icon: "GHA",
      color: "22863a",
    },
    "nvd" => {
      label: "NVD/CVE List",
      icon: "NVD",
      color: "0366d6",
    },
    "cve_review" => {
      label: "CVE Review",
      icon: "CVE",
      color: "735c0f",
    },
    "rubysec" => {
      label: "RubySec",
      icon: "RUB",
      color: "701516",
    },
    "friends_of_php" => {
      label: "FriendsOfPHP",
      icon: "PHP",
      color: "4f5d95",
    },
    "rustsec" => {
      label: "RustSec",
      icon: "RUS",
      color: "dea584",
    },
    "advisory_improvement" => {
      label: "GitHub Advisory Improvement",
      icon: "GAI",
      color: "218283",
    },
    "pypa_advisory" => {
      label: "PyPa Security Advisory",
      icon: "PIP",
      color: "218253",
    },
    "backfill" => {
      label: "Backfill",
      icon: "BKF",
      color: "24292e",
    },
    "malware_advisory" => {
      label: "Malware",
      icon: "MAL",
      color: "cf222e",
    },
    "go" => {
      label: "Go",
      icon: "GO",
      color: "00add8",
    },
  }.freeze
end
