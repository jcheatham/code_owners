Utility gem for .github/CODEOWNERS introspection

GitHub's [CODEOWNERS rules](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners) are allegedly based on the gitignore format with a few small exceptions.

Install
=======

    gem install code_owners

Requirements
============

* Ruby
* Git

Usage
=====

    your/repo/path$ code_owners

Output
======

```
vendor/cache/cloudfiles-1.4.16.gem                                                                   UNOWNED
vendor/cache/code_owners-1.0.1.gem                                                                   jcheatham per line 213, vendor/*/code_owners*
vendor/cache/coderay-1.1.0.gem                                                                       UNOWNED
```

Development
======

Maybe put it in a cleanliness test, like:

```ruby
it "does not introduce new unowned files" do
  unowned_files = CodeOwners.ownerships.select { |f| f[:owner] == CodeOwners::NO_OWNER }
  # this number should only decrease, never increase!
  assert_equal 12345, unowned_files.count, "Claim ownership of your new files in .github/CODEOWNERS to fix this test!"
end
```

Author
======
[Jonathan Cheatham](http://github.com/jcheatham)<br/>
coaxis@gmail.com<br/>
License: MIT
