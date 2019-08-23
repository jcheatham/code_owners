require 'code_owners'
require 'tmpdir'

RSpec.describe CodeOwners do |rspec|
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
          { file: "pat2file", owner: "own2", line: 2, pattern: "pat2*" },
          { file: "unowned/file", owner: "UNOWNED", line: nil, pattern: nil }
        ]
      )
    end
  end

  describe ".pattern_owners" do
    around(:each) do |example|
      Dir.mktmpdir { |d|
        @d = d
        f = File.new(File.join(@d, 'CODEOWNERS'), 'w+')
        @codeowners_content = <<-CODEOWNERS
lib/* @jcheatham
some/path/** @someoneelse
other/path/* @someoneelse @anotherperson
invalid/codeowners/line 
     @AnotherInvalidLine
#comment-line (empty line next)

# another comment line
# Then the following should take precedence over the above
lib/some/specific/path.rb @someonespecific
other/path/something.txt @someonenew
CODEOWNERS
        f.write @codeowners_content
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
      expect(CodeOwners).to receive(:log).with("Parse error line 4: \"invalid/codeowners/line \"")
      expect(CodeOwners).to receive(:log).with("Parse error line 5: \"     @AnotherInvalidLine\"")
      pattern_owners = CodeOwners.pattern_owners
      expect(pattern_owners).not_to include(["", "@AnotherInvalidLine"])
      expect(pattern_owners).to include(["", ""])
    end

    it "respects order-based precedence of ownership rules" do
      Dir.chdir(@d) do
        # For this test we actually need to get Git involved, so we need a dummy repo
        `git init ./
        mkdir -p some/path other/path lib/some/specific
        touch lib/some/specific/path.rb
        touch other/path/something.txt
        git add ./
        git commit -a -m "initial commit"`

        owner_info = CodeOwners.ownerships.map { |h| "#{h[:file]}::#{h[:owner]}::#{h[:line]}" }
        expect(owner_info).to include('lib/some/specific/path.rb::@someonenew::10')
      end
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
  end
end
