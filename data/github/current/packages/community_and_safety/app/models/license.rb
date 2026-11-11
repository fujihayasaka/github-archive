# typed: true
# frozen_string_literal: true

class License < Licensee::License
  include GitHub::Relay::GlobalIdentification

  @all = {}
  @keys_licenses = {}

  IDS_TO_LICENSES = {
    -1 => "no-license", # stored in DB as the absence of a repository license relationship
    0  => "other",
    1  => "agpl-3.0",
    2  => "apache-2.0",
    3  => "artistic-2.0",
    4  => "bsd-2-clause",
    5  => "bsd-3-clause",
    6  => "cc0-1.0",
    7  => "epl-1.0",
    8  => "gpl-2.0",
    9  => "gpl-3.0",
    10 => "isc",
    11 => "lgpl-2.1",
    12 => "lgpl-3.0",
    13 => "mit",
    14 => "mpl-2.0",
    15 => "unlicense",
    16 => "osl-3.0",
    17 => "ofl-1.1",
    18 => "wtfpl",
    19 => "ms-pl",
    20 => "ms-rl",
    21 => "bsd-3-clause-clear",
    22 => "afl-3.0",
    23 => "lppl-1.3c",
    24 => "eupl-1.1",
    25 => "cc-by-4.0",
    26 => "cc-by-sa-4.0",
    27 => "zlib",
    28 => "bsl-1.0",
    29 => "ncsa",
    30 => "ecl-2.0",
    31 => "postgresql",
    32 => "epl-2.0",
    33 => "upl-1.0",
    34 => "eupl-1.2",
    35 => "0bsd",
    36 => "cecill-2.1",
    37 => "odbl-1.0",
    39 => "bsd-4-clause",
    40 => "vim",
    41 => "mit-0",
    42 => "mulanpsl-2.0",
    43 => "cern-ohl-p-2.0",
    44 => "cern-ohl-s-2.0",
    45 => "cern-ohl-w-2.0",
    46 => "gfdl-1.3",
    47 => "blueoak-1.0.0",
    48 => "bsd-2-clause-patent",
  }

  LICENSES_TO_IDS = IDS_TO_LICENSES.invert

  LICENSE_FAMILIES = {
    "lgpl"  => ["lgpl-2.1", "lgpl-3.0"],
    "gpl"   => ["gpl-2.0", "gpl-3.0"],
    "cc"    => ["cc-by-4.0", "cc-by-sa-4.0", "cc0-1.0"],
  }

  LICENSE_FAMILY_NAMES = {
    "lgpl" => "GNU Lesser General Public License",
    "gpl"  => "GNU General Public License",
    "cc"   => "Creative Commons",
  }.freeze

  # A mapping of rule groups to octicons
  RULES_OCTICONS = {
    permissions: "check",
    limitations: "x",
    conditions:  "info",
  }

  # A mapping of rule groups to CSS classes
  RULES_OCTICON_CLASSES = {
    permissions: "color-fg-success",
    limitations: "color-fg-danger",
    conditions:  "color-fg-accent",
  }

  # test_helpers/fixtures.rb assumes that if a fixture responds to #find,
  # the argument it accepts is the object's ID. Here, we use the license
  # key. Wrap the native #find with a helper to allow test fixtures to be
  # properly reinstantiated after each test run.
  def self.find(key_or_id, options = {})
    if key_or_id.is_a?(Integer)
      find_by_id(key_or_id)
    else
      super(key_or_id, options)
    end
  end

  # Returns an array of known license (numeric) IDs for use in validation
  def self.valid_license_ids
    @valid_license_ids ||= IDS_TO_LICENSES.keys
  end

  # All licenses, with featured licenses sorted first.
  #
  # Returns an Array of License objects
  def self.sorted_list
    @sorted ||= all.
      sort_by { |l| l.name.to_s }.
      partition { |license| license.featured? }.
      flatten
  end

  # Find a license by its numeric ID.
  #
  # Returns the license object.
  def self.find_by_id(id)  # rubocop:disable GitHub/FindByDef
    key = IDS_TO_LICENSES[id]
    find(key, hidden: true) if key
  end

  # Generate license data by processing mustaches in the source document.
  #
  # repository - The Repository object that the license is being generated for
  # if field values aren't being passed in.
  #
  # These attributes are available to the template:
  #
  # description - The project's description.
  # email       - The user's public profile email address.
  # fullname    - The user's full name, or their username if no full name.
  # login       - The user's github login.
  # project     - The name of the project / repository.
  # year        - The current year (e.g. 2012)
  #
  # Returns the string result of interpolating the license body.
  def generate(repository: nil, field_values: nil)
    field_values ||= field_values_for_repository(repository)
    Mustache.render(content_for_mustache, field_values)
  end

  # Returns the numeric ID of the license
  def id
    @id ||= LICENSES_TO_IDS[key]
  end

  # Used to generate etags for the API
  def last_modified_at
    Licensee::VERSION
  end

  def field_values_for_repository(repository)
    return {} unless repository
    owner = repository.owner

    {
      "description" => repository.description,
      "email"       => owner.profile.try(:email),
      "fullname"    => owner.profile.try(:name) || owner.login,
      "login"       => owner.login,
      "project"     => repository.name,
      "year"        => Time.now.year,
    }
  end

  def body_as_string
    body.to_s
  end
end
