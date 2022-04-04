#!/usr/bin/env ruby

require 'code_owners'
require 'tmpdir'
require 'json'
require 'pathname'
require 'byebug'

output = { permutations: {} }

def reset_file_to(file, content)
  file.rewind
  file.write(content)
  file.flush
  file.truncate(file.pos)
end

# UGGGGGH
# so, turns out, the part in git-scm where it says
# > A trailing "/**" matches everything inside. For example, "abc/**" matches all files inside directory "abc", relative to the location of the .gitignore file, with infinite depth.
# that "relative" bit gets REAL obnoxious when it comes to trying to evaluate using an adhoc core.excludesFile directive
# speaking of, it seems like if you have one defined in the tree of a project git will STILL use that
# see the special exception case mentioned below for the *.gem pattern conflicting with the project's .gitignore
# there was no way to replace/unset it I could find that doesn't affect something more permanent >:/

ignore_file = File.open("spec/files/.gitignore", "w+")

Dir.chdir("spec/files") do
  all_files = Dir.glob(File.join("**","**"), File::FNM_DOTMATCH)
  all_files.reject! { |f| File.directory?(f) }
  output[:all_files] = all_files

  permutables = ["", "*", ".", "/", "*/", "/*", "**", "**/", "/**", "**/**", "*/**", "**/*"]
  ignore_cases = permutables.map do |p1|
    ["foo", "bar", "foo/bar"].map do |p2|
      permutables.map do |p3|
        "#{p1}#{p2}#{p3}"
      end
    end
  end.flatten

  # can add more one-off cases we want to evaluate here
  ignore_cases << ".dot*"

  ignore_cases.sort!
  puts "Evaluating #{ignore_cases.size} permutations"

  rootpath = Pathname.new(".")

  ignore_cases.each do |perm|
    puts "evaluating #{perm}"
    reset_file_to(ignore_file, perm)
    ignore_matches = []
    ignore_results = `find . -type f | sed "s|^\./||" | tr '\n' '\\0' | xargs -0 -- git -c "core.quotepath=off" check-ignore --no-index -v -n`
    ignore_results.scan(/^([^:]+):(\d+):([^\t]*)\t(.*)/).each do |m_source, m_line, m_pattern, m_file|
      if m_source != ignore_file.path || m_line != "1" || m_pattern != perm
        next if m_source == ".gitignore" && m_line == "1" && m_pattern == "*.gem"
        puts "ERROR?!"
        puts "expecting #{ignore_file.path.inspect}, got #{m_source.inspect}"
        puts "expecting 1, got #{m_line.inspect}"
        puts "expecting #{perm.inspect}, got #{m_pattern.inspect}"
        puts ignore_results
      end
      ignore_matches << Pathname.new(m_file).relative_path_from(rootpath).to_s
    end
    output[:permutations][perm] = ignore_matches.sort
  end

  reset_file_to(ignore_file, "blah blah blah")
end

File.open("spec/permutations.json", "w+") do |perm_file|
  perm_file.write(JSON.pretty_generate(output))
end
