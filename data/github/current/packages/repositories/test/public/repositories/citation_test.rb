# typed: true
# frozen_string_literal: true

require "test_helper"

class Repositories::CitationTest < GitHub::TestCase
  include DogstatsTestHelpers

  class FakeTreeEntry
    attr_reader :data, :repository
    def initialize(data, repository)
      @data = data
      @repository = repository
    end
  end

  fixtures do
    @repository = create(:repository)
    @community_repo = create(:repository)
    @repository_citation_md = create(:repository)
    @citation_on_branch_repo = create(:repository)
  end

  setup do
    example_repo :citation, @repository
    example_repo :community_files, @community_repo
    example_repo :citation_md, @repository_citation_md
    example_repo :citation_on_branch, @citation_on_branch_repo
  end

  context "#from_repository" do
    test "specific tree_name" do
      tree_name = @citation_on_branch_repo.heads.first.name
      c = Repositories::Citation.from_repository(@citation_on_branch_repo, tree_name: tree_name)
      assert_match "#{@citation_on_branch_repo.nwo}/blob/#{tree_name}/CITATION.md", c.file_path
    end

    test "non specific tree_name" do
      c = Repositories::Citation.from_repository(@community_repo)
      formatted = c.format(:apa)
      refute_match "Patrick", formatted
    end
  end

  test "with included, but empty fields" do
    citation = <<-CIT
cff-version: 1.1.0
message: "If you use this software, please cite it as below."
authors:
  - family-names: Druskat
    given-names: Stephan
    orcid: https://orcid.org/0000-0003-4925-7248
title: "My Research Software"
version: 2.0.4
doi: 10.5281/zenodo.1234
date-released: 2017-12-18

keywords:
CIT
    # Keywords is specified, but is empty
    tree_entry = FakeTreeEntry.new(citation, nil)

    c = Repositories::Citation.new(tree_entry)
    assert c.valid?
    formatted = c.format(:apa)
    assert_match "Druskat", formatted
  end

  context "#format" do
    test "format apalike" do
      c = Repositories::Citation.from_repository(@repository)
      assert c.valid?
      refute_nil c.format(:apa)
    end

    test "format bibtex" do
      c = Repositories::Citation.from_repository(@repository)
      assert c.valid?
      refute_nil c.format(:bibtex)
    end

    test "attempting to format an invalid Citation returns nil" do
      invalid_yaml = "'- that quotation mark means trouble"
      tree_entry = TreeEntry.new(@repository, { "data" => invalid_yaml })

      invalid_citation = Repositories::Citation.new(tree_entry)
      refute invalid_citation.valid?
      assert_nil invalid_citation.format(:bibtex)
      assert_dogstats_increment(1, "citation.parse.error", tags: ["error:Psych::SyntaxError"])
    end

    test "attempting to format an invalid references returns nil" do
      invalid_yaml = <<-CIT
references:
  type: article
  title: "Cool title"
  year: 2023
license: Apache-2.0
CIT

      tree_entry = TreeEntry.new(@repository, { "data" => invalid_yaml })

      invalid_citation = Repositories::Citation.new(tree_entry)
      refute invalid_citation.valid?
      assert_nil invalid_citation.format(:bibtex)
      assert_dogstats_increment(1, "citation.parse.error", tags: ["error:NoMethodError"])
    end

    test "attempting to format a valid citation file that's not CITATION.cff" do
      c = Repositories::Citation.from_repository(@repository_citation_md)
      refute c.valid?
      assert_nil c.format(:bibtex)
    end
  end

  context "#valid?" do
    test "catches CFF error" do
      cit = <<-CIT
title: Causes CFF to throw an error
type: conference-paper
conference:
  name: Cool Event
  address: Virtual
authors:
  - given-names: Jess
    family-names: Smith
CIT

      tree_entry = TreeEntry.new(@repository, { "data" => cit })

      invalid_citation = Repositories::Citation.new(tree_entry)
      refute invalid_citation.valid?
      assert_nil invalid_citation.format(:bibtex)
      assert_nil invalid_citation.format(:apa)
      assert_dogstats_increment(0, "citation.parse.error")
      assert_dogstats_increment(3, "citation.valid.error", tags: ["error:NoMethodError"])
    end
  end
end
