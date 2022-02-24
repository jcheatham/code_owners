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
    around(:each) do |example|
      Dir.mktmpdir { |d|
        @d = d
        f = File.new(File.join(d, 'CODEOWNERS'), 'w+')
        f.write <<-CODEOWNERS
lib/* @jcheatham
some/path/** @someoneelse
other/path/* @someoneelse @anotherperson
invalid/code owners/line
     @AnotherInvalidLine
#comment-line (empty line next)

# another comment line
CODEOWNERS
        f.close
        example.run
      }
    end

    it "returns a list of patterns and owners" do
      expect(CodeOwners).to receive(:current_repo_path).and_return(@d)
      expect(CodeOwners).to receive(:log).twice
      pattern_owners = CodeOwners.pattern_owners
      expect(pattern_owners).to include(["other/path/*", "@someoneelse @anotherperson"])
    end

    it "works when invoked in a repo's subdirectory" do
      expect(CodeOwners).to receive(:current_repo_path).and_return(@d)
      expect(CodeOwners).to receive(:log).twice
      subdir = File.join(@d, 'spec')
      Dir.mkdir(subdir)
      Dir.chdir(subdir) do
        pattern_owners = CodeOwners.pattern_owners
        expect(pattern_owners).to include(["lib/*", "@jcheatham"])
      end
    end

    it "prints validation errors and skips lines that aren't the expected format" do
      expect(CodeOwners).to receive(:current_repo_path).and_return(@d)
      expect(CodeOwners).to receive(:log).with("Parse error line 4: \"invalid/code owners/line\"")
      expect(CodeOwners).to receive(:log).with("Parse error line 5: \"     @AnotherInvalidLine\"")
      pattern_owners = CodeOwners.pattern_owners
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
