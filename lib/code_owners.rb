require "code_owners/version"
require "tempfile"

module CodeOwners
  NO_OWNER = 'UNOWNED'
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

    def log(message)
      puts message
    end

    def ownerships
      patterns = pattern_owners
      git_owner_info(patterns.map { |p| p[0] }).map do |line, pattern, file|
        if line.empty?
          { file: file, owner: NO_OWNER, line: nil, pattern: nil }
        else
          {
            file: file,
            owner: patterns.fetch(line.to_i-1)[1],
            line: line,
            pattern: pattern
          }
        end
      end
    end

    def search_codeowners_file
      paths = ["CODEOWNERS", "docs/CODEOWNERS", ".github/CODEOWNERS"]
      for path in paths
        current_file_path = File.join(current_repo_path, path)
        return current_file_path if File.exist?(current_file_path)
      end
      abort("[ERROR] CODEOWNERS file does not exist.")
    end

    # read the github file and spit out a slightly formatted list of patterns and their owners
    # Empty/invalid/commented lines are still included in order to preserve line numbering
    def pattern_owners
      codeowner_path = search_codeowners_file
      patterns = []
      File.read(codeowner_path).split("\n").each_with_index { |line, i|
        path_owner = line.split(/\s+@/, 2)
        if line.match(/^\s*(?:#.*)?$/)
          patterns.push ['', ''] # Comment/empty line
        elsif path_owner.length != 2 || (path_owner[0].empty? && !path_owner[1].empty?)
          log "Parse error line #{(i+1).to_s}: \"#{line}\""
          patterns.push ['', ''] # Invalid line
        else
          path_owner[1] = '@'+path_owner[1]
          patterns.push path_owner
        end
      }
      return patterns
    end

    def git_owner_info(patterns)
      make_utf8(raw_git_owner_info(patterns)).lines.map do |info|
        _, _exfile, line, pattern, file = info.strip.match(/^(.*):(\d*):(.*)\t(.*)$/).to_a
        [line, pattern, file]
      end
    end

    # expects an array of gitignore compliant patterns
    # generates a check-ignore formatted string for each file in the repo
    def raw_git_owner_info(patterns)
      Tempfile.open('codeowner_patterns') do |file|
        file.write(patterns.join("\n"))
        file.rewind
        `cd #{current_repo_path} && git -c \"core.quotepath=off\" ls-files -z | xargs -0 -- git -c \"core.quotepath=off\" -c \"core.excludesfile=#{file.path}\" check-ignore --no-index -v -n`
      end
    end

    private

    def make_utf8(input)
      input.force_encoding(Encoding::UTF_8)
      return input if input.valid_encoding?
      input.encode!(Encoding::UTF_16, invalid: :replace, replace: '�')
      input.encode!(Encoding::UTF_8, Encoding::UTF_16)
      input
    end

    def current_repo_path
      `git rev-parse --show-toplevel`.strip
    end
  end
end
