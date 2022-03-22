require "code_owners/version"
require "tempfile"

module CodeOwners

  NO_OWNER = 'UNOWNED'
  CODEOWNER_PATTERN = /(.*?)\s+((?:[^\s]*@[^\s]+\s*)+)/

  class << self

    # helper function to create the lookup for when we have a file and want to find its owner
    def file_ownerships
      Hash[ ownerships.map { |o| [o[:file], o] } ]
    end

    # this maps the collection of ownership patterns and owners to actual files
    def ownerships
      codeowner_path = search_codeowners_file
      patterns = pattern_owners(File.read(codeowner_path))
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

    # read the github file and spit out a slightly formatted list of patterns and their owners
    # Empty/invalid/commented lines are still included in order to preserve line numbering
    def pattern_owners(codeowner_data)
      patterns = []
      codeowner_data.split("\n").each_with_index do |line, i|
        stripped_line = line.strip
        if stripped_line == "" || stripped_line.start_with?("#")
          patterns << ['', ''] # Comment / empty line

        elsif stripped_line.start_with?("!")
          # unsupported per github spec
          log "Parse error line #{(i+1).to_s}: \"#{line}\""
          patterns << ['', '']

        elsif stripped_line.match(CODEOWNER_PATTERN)
          patterns << [$1, $2]

        else
          log "Parse error line #{(i+1).to_s}: \"#{line}\""
          patterns << ['', '']

        end
      end
      patterns
    end

    def git_owner_info(patterns)
      make_utf8(raw_git_owner_info(patterns)).lines.map do |info|
        _, _exfile, line, pattern, file = info.strip.match(/^(.*):(\d*):(.*)\t(.*)$/).to_a
        [line, pattern, file]
      end
    end

    # IN: an array of gitignore* check-ignore compliant patterns
    # OUT: a check-ignore formatted string for each file in the repo
    #
    # * https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners#syntax-exceptions
    # sadly you can't tell ls-files to ignore tracked files via an arbitrary pattern file
    # so we jump through some hacky git-fu hoops
    #
    # -c "core.quotepath=off" ls-files -z   # prevent quoting the path and null-terminate each line to assist with matching stuff with spaces
    # -c "core.excludesfiles=somefile"      # tells git to use this as our gitignore pattern source
    # check-ignore                          # debug gitignore / exclude files
    # --no-index                            # don't look in the index when checking, can be used to debug why a path became tracked
    # -v                                    # verbose, outputs details about the matching pattern (if any) for each given pathname
    # -n                                    # non-matching, shows given paths which don't match any pattern
    def raw_git_owner_info(patterns)
      Tempfile.open('codeowner_patterns') do |file|
        file.write(patterns.join("\n"))
        file.rewind
        `cd #{current_repo_path} && git -c \"core.quotepath=off\" ls-files -z | xargs -0 -- git -c \"core.quotepath=off\" -c \"core.excludesfile=#{file.path}\" check-ignore --no-index -v -n`
      end
    end

    # https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners#codeowners-file-location
    # To use a CODEOWNERS file, create a new file called CODEOWNERS in the root, docs/, or .github/ directory of the repository, in the branch where you'd like to add the code owners.
    def search_codeowners_file
      paths = ["CODEOWNERS", "docs/CODEOWNERS", ".github/CODEOWNERS"]
      for path in paths
        current_file_path = File.join(current_repo_path, path)
        return current_file_path if File.exist?(current_file_path)
      end
      abort("[ERROR] CODEOWNERS file does not exist.")
    end

    def log(message)
      puts message
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
