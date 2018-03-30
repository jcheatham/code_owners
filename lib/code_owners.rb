require "code_owners/version"
require "tempfile"

module CodeOwners
  class << self
    # github's CODEOWNERS rules (https://help.github.com/articles/about-codeowners/) are allegedly based on the gitignore format.
    # but you can't tell ls-files to ignore tracked files via an arbitrary pattern file
    # so we need to jump through some hacky git-fu hoops
    #
    # -c "core.excludesfiles=somefile" -> tells git to use this as our gitignore pattern source
    # check-ignore -> debug gitignore / exclude files
    # --no-index -> don't look in the index when checking, can be used to debug why a path became tracked
    # -v -> verbose, outputs details about the matching pattern (if any) for each given pathname
    # -n -> non-matching, shows given paths which don't match any pattern

    def ownerships
      patterns, owners = pattern_owners.transpose

      raw_git_ownership(patterns).map do |status|
        _, _exfile, line, pattern, file = status.match(/^(.*):(\d*):(.*)\t(.*)$/).to_a
        if line.empty?
          { file: file, owner: "UNOWNED" }
        else
          { file: file, owner: owners[line.to_i - 1], line: line, pattern: pattern }
        end
      end
    end

    # read the github file and spit out a slightly formatted list of patterns and their owners
    def pattern_owners
      current_repo_path = `git rev-parse --show-toplevel`.strip
      codeowner_path = File.join(current_repo_path, ".github/CODEOWNERS")
      File.read(codeowner_path).split("\n").map do |line|
        line.gsub(/#.*/, '').gsub(/^$/, " @").split(/\s+@/, 2)
      end
    end

    # expects an array of gitignore compliant patterns
    # generates a check-ignore formatted string for each file in the repo
    def raw_git_ownership(patterns)
      Tempfile.open('codeowner_patterns') do |file|
        file.write(patterns.join("\n"))
        file.rewind
        cmd = "git ls-files | xargs -- git -c \"core.excludesfile=#{file.path}\" check-ignore --no-index -v -n"
        `#{cmd}`.lines.map(&:strip)
      end
    end
  end
end
