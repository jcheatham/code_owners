require 'code_owners'
require 'tmpdir'

RSpec.describe CodeOwners do |rspec|
  describe ".file_ownerships" do
    it "returns a hash of ownerships keyed by file path" do
      expect(CodeOwners).to receive(:ownerships).and_return(
        [
          { file: "pat2file", owner: "own2", line: "2", pattern: "pat2*" },
          { file: "unowned/file", owner: "UNOWNED", line: nil, pattern: nil }
        ]
      )
      expect(CodeOwners.file_ownerships).to eq(
        {
          "pat2file" => { file: "pat2file", owner: "own2", line: "2", pattern: "pat2*" },
          "unowned/file" => { file: "unowned/file", owner: "UNOWNED", line: nil, pattern: nil }
        }
      )
    end
  end

  describe ".ownerships" do
    it "assigns owners to things" do
      expect(CodeOwners).to receive(:pattern_owners).and_return([["pat1", "own1"], ["pat2*", "own2"], ["pat3", "own3"]])
      expect(CodeOwners).to receive(:git_owner_info).and_return(
        [
          ["2", "pat2*", "pat2file"],
          ["", "", "unowned/file"]
        ]
      )
      expect(CodeOwners.ownerships).to eq(
        [
          { file: "pat2file", owner: "own2", line: "2", pattern: "pat2*" },
          { file: "unowned/file", owner: "UNOWNED", line: nil, pattern: nil }
        ]
      )
    end
  end

  describe ".pattern_owners" do
    before do
      @data = <<-CODEOWNERS
lib/* @jcheatham
some/path/** @someoneelse
other/path/* @someoneelse @anotherperson

this path/has spaces.txt        @spacelover spacer@example.com
/this also has spaces.txt        spacer@example.com @spacelover

invalid/code owners/line
     @AnotherInvalidLine
#comment-line (empty line next)
!this/is/unsupported.txt   @foo
here/is/a/valid/path.txt   @jcheatham

#/another/comment/line @nobody
CODEOWNERS
    end

    it "returns an empty array given an empty string" do
      results = CodeOwners.pattern_owners("")
      expect(results).to eq([])
    end

    it "returns a list of patterns and owners" do
      expected_results = [
        ["lib/*", "@jcheatham"],
        ["some/path/**", "@someoneelse"],
        ["other/path/*", "@someoneelse @anotherperson"],
        ["", ""],
        ["this path/has spaces.txt", "@spacelover spacer@example.com"],
        ["/this also has spaces.txt", "spacer@example.com @spacelover"],
        ["", ""],
        ["", ""],
        ["", ""],
        ["", ""],
        ["", ""],
        ["here/is/a/valid/path.txt", "@jcheatham"],
        ["", ""],
        ["", ""]]

      expect(CodeOwners).to receive(:log).exactly(3).times
      results = CodeOwners.pattern_owners(@data)
      # do this to compare elements with much nicer failure hints
      expect(results).to match_array(expected_results)
      # but do this to guarantee order
      expect(results).to eq(expected_results)
    end

    it "prints validation errors and skips lines that aren't the expected format" do
      expect(CodeOwners).to receive(:log).with("Parse error line 8: \"invalid/code owners/line\"")
      expect(CodeOwners).to receive(:log).with("Parse error line 9: \"     @AnotherInvalidLine\"")
      expect(CodeOwners).to receive(:log).with("Parse error line 11: \"!this/is/unsupported.txt   @foo\"")
      pattern_owners = CodeOwners.pattern_owners(@data)
      expect(pattern_owners).not_to include(["", "@AnotherInvalidLine"])
      expect(pattern_owners).to include(["", ""])
    end
  end

  describe ".git_owner_info" do
    it "returns a massaged list of git ownership info" do
      expect(CodeOwners).to receive(:raw_git_owner_info).and_return("this_gets_discarded:2:whatever/pattern/thing\tthis/is/a/file\n::\tBad\xEF\xEF\xEF\xEF chars\xC3\xA5\xE2\x88\x86\xC6\x92.txt" )
      expect(CodeOwners.git_owner_info(["/lib/*"])).to eq(
        [
          ["2", "whatever/pattern/thing", "this/is/a/file"],
          ["", "", "Bad���� charså∆ƒ.txt"]
        ]
      )
    end
  end

  describe ".raw_git_owner_info" do
    it "establishes code owners from a list of patterns" do
      raw_ownership = CodeOwners.raw_git_owner_info(["/lib/*"])
      expect(raw_ownership.size).to be >= 1
      expect(raw_ownership).to match(/^(?:.*:\d*:.*\t.*\n)+$/)
    end

    context "when path includes a space" do
      it "returns the path in single line" do
        raw_ownership = CodeOwners.raw_git_owner_info(["/spec/files/*"])
        expect(raw_ownership).to match(/.+:\d+:.+\tspec\/files\/file name\.txt\n/)
      end
    end
  end

  describe "code_owners" do
    VERSION_REGEX = /Version: \d+\.\d+\.\d+(-[a-z0-9]+)?/i

    it "prints a version number with the short option" do
      expect(`bin#{File::SEPARATOR}code_owners -v`).to match VERSION_REGEX
    end

    it "prints a version number with the short option" do
      expect(`bin#{File::SEPARATOR}code_owners --version`).to match VERSION_REGEX
    end
  end
end
