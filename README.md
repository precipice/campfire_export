# campfire-export #

I had an old, defunct [Campfire](http://campfirenow.com/) account with five
years' worth of transcripts in it, some of them hilarious, others just 
memorable. Unfortunately, Campfire doesn't currently have an export function;
instead it provides pages of individual transcripts. I wanted a script to
export everything from all five years, using the Campfire API.

I found a [Gist](https://gist.github.com) that looked pretty good:

* [https://gist.github.com/821553](https://gist.github.com/821553)

but it wasn't quite right. So this is my modification, converted to a GitHub
repo.

## Features ##

* Saves HTML, XML, and plaintext versions of chat transcripts.
* Exports uploaded files to a day-specific subdirectory for easy access.
* Reports and logs export errors so you know what you're missing.

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

There are a number of configuration variables required to run the export.
Copy the `campfire_config-template.yaml` file from this project to 
`.campfire_config.yaml` in your home directory, and then modify it
as described in that file.

The `START_DATE` and `END_DATE` variables are inclusive (that is, if your
end date is Dec 31, 2010, a transcript for that date will be downloaded).

## Exporting ##

Just run `ruby campfire_export.rb` and your transcripts will be exported into
a `campfire` directory, with subdirectories for each site/room/year/month/day.
In those directories, any uploaded files will be saved with their original
filenames, prepended by the upload ID (since transcripts often have the same
filename uploaded multiple times, e.g. `Picture 1.png`). (Note that rooms and
uploaded files may have odd filenames -- for instance, spaces in the
file/directory names.) Errors that happen trying to export will be logged to
`campfire/export_errors.txt`.

The Gist I forked had a plaintext transcript export, which I preserved as
`transcript.txt` in each directory. However, the original XML and HTML are now
also saved as `transcript.xml` and `transcript.html`, which could be useful.

Days which have no messages posted will be ignored, so the resulting directory
structure will be sparse (no messages == no directory).

## Limitations ##

* Room name changes are not noticed.
* Slow as all hell if you have file uploads.

## Credit ##

As mentioned above, much of the work on this was done by other people. The
Gist I forked had contributions from:

* [Pat Allan](https://github.com/freelancing-god)
* [Bruno Mattarollo](https://github.com/bruno)
* [bf4](https://github.com/bf4)

Also, thanks for comments and contributions:

* [Brad Greenlee](https://github.com/bgreenlee)

Thanks, all!

- Marc Hedlund, marc@precipice.org