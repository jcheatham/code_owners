require 'code_owners'

RSpec.describe CodeOwners do
  describe ".ownerships" do
    it "assigns owners to things" do
      expect(CodeOwners).to receive(:pattern_owners).and_return([["pat1", "own1"], ["pat2", "own2"], ["pat3", "own3"]])
      expect(CodeOwners).to receive(:raw_git_ownership).and_return(
        [
          "this_gets_discarded:2:whatever/pattern/thing\tthis/is/a/file",
          "::\tunowned/file"
        ]
      )
      expect(CodeOwners.ownerships).to eq(
        [
          { file: "this/is/a/file", owner: "own2", line: "2", pattern: "whatever/pattern/thing" },
          { file: "unowned/file",   owner: "UNOWNED"}
        ]
      )
    end
  end

  describe ".pattern_owners" do
    it "returns a list of patterns and owners" do
      patterns, owners = CodeOwners.pattern_owners.transpose
      expect(owners).to include("jcheatham")
      expect(patterns).to include("lib/*")
    end
  end

  describe ".raw_git_ownership" do
    it "establishes code owners from a list of patterns" do
      raw_ownership = CodeOwners.raw_git_ownership(["/lib/*"])
      expect(raw_ownership.size).to be >= 1
      expect(raw_ownership).to all( match(/^.*:\d*:.*\t.*$/) )
    end
  end
end
