require "code_owners/version"
require "tempfile"
require "pathspec"

module CodeOwners

  NO_OWNER = 'UNOWNED'
  CODEOWNER_PATTERN = /(.*?)\s+((?:[^\s]*@[^\s]+\s*)+)/
  POTENTIAL_LOCATIONS = ["CODEOWNERS", "docs/CODEOWNERS", ".github/CODEOWNERS"]

  class << self

    # helper function to create the lookup for when we have a file and want to find its owner
    def file_ownerships(opts = {})
      Hash[ ownerships(opts).map { |o| [o[:file], o] } ]
    end

    # this maps the collection of ownership patterns and owners to actual files
    def ownerships(opts = {})
      log("Calculating ownerships for #{opts.inspect}", opts)
      patowns = pattern_owners(codeowners_data(opts), opts)
      if opts[:no_git]
        files = files_to_own(opts)
        ownerships_by_ruby(patowns, files, opts)
      else
        ownerships_by_gitignore(patowns, opts)
      end
    end


    ####################
    # gitignore approach

    def ownerships_by_gitignore(patterns, opts = {})
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


    ###############
    # ruby approach

    def ownerships_by_ruby(patowns, files, opts = {})
      pattern_list = build_ruby_patterns(patowns, opts)
      unowned = { owner: NO_OWNER, line: nil, pattern: nil }

      files.map do |file|
        last_match = nil
        # have a flag to go through in reverse order as potential optimization?
        # really depends on the data
        pattern_list.each do |p|
          last_match = p if p[:pattern_regex].match(file)
        end
        (last_match || unowned).dup.tap{|h| h[:file] = file }
      end
    end

    def build_ruby_patterns(patowns, opts = {})
      pattern_list = []
      patowns.each_with_index do |(pattern, owner), i|
        next if pattern == ""
        pattern_list << {
          owner: owner,
          line: i+1,
          pattern: pattern,
          # gsub because spec approach needs a little help matching remainder of tree recursively
          pattern_regex: PathSpec::GitIgnoreSpec.new(pattern.gsub(/\/\*$/, "/**"))
        }
      end
      pattern_list
    end


    ##############
    # helper stuff

    # read the github file and spit out a slightly formatted list of patterns and their owners
    # Empty/invalid/commented lines are still included in order to preserve line numbering
    def pattern_owners(codeowner_data, opts = {})
      patterns = []
      codeowner_data.split("\n").each_with_index do |line, i|
        stripped_line = line.strip
        if stripped_line == "" || stripped_line.start_with?("#")
          patterns << ['', ''] # Comment / empty line

        elsif stripped_line.start_with?("!")
          # unsupported per github spec
          log("Parse error line #{(i+1).to_s}: \"#{line}\"", opts)
          patterns << ['', '']

        elsif stripped_line.match(CODEOWNER_PATTERN)
          patterns << [$1, $2]

        else
          log("Parse error line #{(i+1).to_s}: \"#{line}\"", opts)
          patterns << ['', '']

        end
      end
      patterns
    end

    def log(message, opts = {})
      puts message if opts[:log]
    end

    private

    # https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners#codeowners-file-location
    # To use a CODEOWNERS file, create a new file called CODEOWNERS in the root, docs/, or .github/ directory of the repository, in the branch where you'd like to add the code owners.

    # if we have access to git, use that to figure out our current repo path and look in there for codeowners
    # if we don't, this function will attempt to find it while walking back up the directory tree
    def codeowners_data(opts = {})
      if opts[:codeowner_data]
        return opts[:codeowner_data]
      elsif opts[:codeowner_path]
        return File.read(opts[:codeowner_path]) if File.exist?(opts[:codeowner_path])
      elsif opts[:no_git]
        path = Dir.pwd.split(File::SEPARATOR)
        while !path.empty?
          POTENTIAL_LOCATIONS.each do |pl|
            current_file_path = File.join(path, pl)
            return File.read(current_file_path) if File.exist?(current_file_path)
          end
          path.pop
        end
      else
        path = current_repo_path
        POTENTIAL_LOCATIONS.each do |pl|
          current_file_path = File.join(path, pl)
          return File.read(current_file_path) if File.exist?(current_file_path)
        end
      end
      raise("[ERROR] CODEOWNERS file does not exist.")
    end

    def files_to_own(opts = {})
      # glob all files
      all_files_pattern = File.join("**","**")

      # optionally prefix with list of directories to scope down potential evaluation space
      if opts[:scoped_dirs]
        all_files_pattern = File.join("{#{opts[:scoped_dirs].join(",")}}", all_files_pattern)
      end

      all_files = Dir.glob(all_files_pattern, File::FNM_DOTMATCH)
      all_files.reject!{|f| f.start_with?(".git/") || File.directory?(f) }

      # filter out ignores if we have them
      opts[:ignores]&.each do |ignore|
        ignores = PathSpec.new(File.readlines(ignore, chomp: true).map{|i| i.end_with?("/*") ? "#{i}*" : i })
        all_files.reject! { |f| ignores.specs.any?{|p| p.match(f) } }
      end

      all_files
    end

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
