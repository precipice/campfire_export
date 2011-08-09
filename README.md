# campfire_export #

## Quick Start ##

    $ sudo gem install campfire_export
    $ campfire_export

## Intro ##

I had an old, defunct [Campfire](http://campfirenow.com/) account with five
years' worth of transcripts in it, some of them hilarious, others just 
memorable. Unfortunately, Campfire doesn't currently have an export function;
instead it provides pages of individual transcripts. I wanted a script to
export everything from all five years, using the Campfire API.

I found a [Gist](https://gist.github.com) that looked pretty good:

* [https://gist.github.com/821553](https://gist.github.com/821553)

but it wasn't quite right. So this is my modification, converted to a GitHub
repo and a [Ruby gem](http://docs.rubygems.org/read/chapter/1).

## Features ##

* Saves HTML, XML, and plaintext versions of chat transcripts.
* Exports uploaded files to a day-specific subdirectory for easy access.
* Reports and logs export errors so you know what you're missing.
* Obsessively confirms that everything was exported correctly.

## Installing ##

[Ruby 1.8.7](http://www.ruby-lang.org/en/downloads/) or later is required.
[RubyGems](https://rubygems.org/pages/download) is also required -- I'd
recommend having the latest version of RubyGems installed before starting.

Once you are set up, to install, run the following:

    $ sudo gem install campfire_export

## Configuring ##

There are a number of configuration variables required to run the export. The
export script will prompt you for these; just run it and away you go. If you
want to run the script repeatedly or want to control the start and end date of
the export, you can create a `.campfire_export.yaml` file in your home
directory using this template:

    # Your Campfire subdomain (for 'https://myco.campfirenow.com', use 'myco').
    subdomain:  myco

    # Your Campfire API token (see "My Info" on your Campfire site).
    api_token:  abababababababababababababababababababab

    # OPTIONAL: Export start date - the first transcript you want exported.
    # Uncomment to set. Defaults to the date each room was created.
    #start_date: 2010/1/1

    # OPTIONAL: Export end date - the last transcript you want exported.
    # Uncomment to set. Defaults to the date of the last comment in each room.
    #end_date:   2010/12/31

The `start_date` and `end_date` variables are inclusive (that is, if your
end date is Dec 31, 2010, a transcript for that date will be downloaded), and
both are optional. If they are omitted, export will run from the date each
Campfire room was created, until the date of the last message in that room.

## Exporting ##

Just run `campfire_export` and your transcripts will be exported into a
`campfire` directory in the current directory, with subdirectories for each
site/room/year/month/day. In those directories, any uploaded files will be
saved with their original filenames, in a directory named for the upload ID
(since transcripts often have the same filename uploaded multiple times, e.g.
`Picture 1.png`). (Note that rooms and uploaded files may have odd filenames
-- for instance, spaces in the file/directory names.) Errors that happen
trying to export will be logged to `campfire/export_errors.txt`.

The Gist I forked had a plaintext transcript export, which I've kept in as
`transcript.txt` in each directory. However, the original XML and HTML are now
also saved as `transcript.xml` and `transcript.html`, which could be useful.

Days which have no messages posted will be ignored, so the resulting directory
structure will be sparse (no messages == no directory).

## Credit ##

First, thanks a ton to [Jeffrey Hardy](https://github.com/packagethief) from
37signals, who helped me track down some bugs in my code as well as some
confusion in what I was getting back from Campfire. His patient and determined
help made it possible to get this working. Thanks, Jeff!

Also, thanks much for all the help, comments and contributions:

* [Brad Greenlee](https://github.com/bgreenlee)
* [Andre Arko](https://github.com/indirect)
* [Brian Donovan](https://github.com/eventualbuddha)
* [Andrew Wong](https://github.com/andrewwong1221)

As mentioned above, some of the work on this was done by other people. The
Gist I forked had contributions from:

* [Pat Allan](https://github.com/freelancing-god)
* [Bruno Mattarollo](https://github.com/bruno)
* [bf4](https://github.com/bf4)

Thanks, all!

- Marc Hedlund, marc@precipice.org
