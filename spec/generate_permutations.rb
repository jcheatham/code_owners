#!/usr/bin/env ruby

require 'code_owners'
require 'tmpdir'
require 'json'

output = { permutations: {} }

Dir.chdir("spec/files") do
  all_files = Dir.glob(File.join(".","**","**"), File::FNM_DOTMATCH)
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

  Tempfile.open('codeowner_patterns') do |file|
    ignore_cases.each do |perm|
      puts "evaluating #{perm}"
      file.rewind
      file.write(perm)
      file.flush
      file.truncate(file.pos)
      ignore_matches = []
      ignore_results = `find . -type f -print0 | xargs -0 -- git -c "core.quotepath=off" -c "core.excludesfile=#{file.path}" check-ignore --no-index -v -n`
      ignore_results.scan(/^([^:]+):(\d+):([^\t]*)\t(.*)/).each do |m_source, m_line, m_pattern, m_file|
        if m_source != file.path || m_line != "1" || m_pattern != perm
          puts "ERROR?!"
          puts "#{m_source.inspect} == #{file.path.inspect}"
          puts "#{m_line.inspect} == 1"
          puts "#{m_pattern.inspect} == #{perm.inspect}"
          puts ignore_results
        end
        ignore_matches << m_file
      end
      output[:permutations][perm] = ignore_matches.sort
    end
  end
end

File.open("spec/permutations.json", "w+") do |perm_file|
  perm_file.write(JSON.pretty_generate(output))
end
