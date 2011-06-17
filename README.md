# campfire-export #

I had an old, defunct [Campfire](http://campfirenow.com/) account with four 
years' worth of transcripts in it, some of them hilarious, others just 
memorable. Unfortunately, Campfire doesn't currently have an export function;
instead it provides pages of individual transcripts.

I found a [Gist](https://gist.github.com) that looked pretty good:

* [https://gist.github.com/821553](https://gist.github.com/821553)

but it wasn't quite right. So this is my modification, converted to a GitHub
repo.

## Installing ##

Ruby 1.8.7 or later is required.

First, clone the GitHub repo:

    $ git clone git://github.com/precipice/campfire-export.git

If you don't already have [Bundler](http://gembundler.com/) installed, do that
now:

    $ gem install bundler

Then install required gems via Bundler:

    $ bundle install

## Configuring ##

There are a number of configuration variables clearly marked at the top of
`campfire_export.rb`. The script won't run without them. Make sure to edit
them before running the script, and also make sure not to check in your API
token on any public source repo.

The `start_date` and `end_date` variables are inclusive (that is, if your
end date is Dec 31, 2010, a transcript for that date will be downloaded).

## Exporting ##

Just run `ruby campfire_export.rb` and your transcripts will be exported 
into a `campfire` directory, with subdirectories for each room/year/month/day. 
In those directories, any uploaded files will be saved with their original
filenames. (Note that rooms and uploaded files may have odd filenames -- for
instance, spaces in the file/directory names.)

The Gist I forked had a plaintext transcript export, which I preserved as
`transcript.txt` in each directory. However, the original XML is now also
saved as `transcript.xml`, which could be useful for programmatic access to
the transcripts.

Days which have no messages posted will be ignored, so the resulting directory
structure will be sparse (no messages == no directory).

## Limitations ##

* No error checking of almost any kind.
* Room name changes are not noticed.
* Slow as all hell if you have file uploads (which are on S3).

## Credit ##

As mentioned above, nearly all the work on this was done by other people. The
Gist I forked had contributions from:

* [Pat Allan](https://github.com/freelancing-god)
* [Bruno Mattarollo](https://github.com/bruno)
* [bf4](https://github.com/bf4)

Also, thanks for comments and contributions:

* [Brad Greenlee](https://github.com/bgreenlee)

Thanks, all!

- Marc Hedlund, marc@precipice.org