Seashell
========

A Bash client for the DigitalOcean API

Uses a nearly-unmodified version of Dominic Tarr's amazing bash-based JSON parser [JSON.sh](https://github.com/dominictarr/JSON.sh), included as a function.

There is currently only a proof-of-concept script here, along with the LICENSE and README files.

**THE CURRENT STATUS OF THE POC SCRIPT IS DISPLAY-ONLY!**

**UPDATE 2013-09-25 - This has been on hold for a while due to the pending release of API v2.0.**  
**Development will resume (and probably restart) when API v2.0 is released by DigitalOcean.**

It will be updated as frequently as time permits, and the next step is to incorporate actual actions such as creating/destroying droplets, etc.

Since this code is currently in a pre-alpha state, please don't bother submitting pull requests, bug reports, etc. yet, as they will likely be ignored until the script becomes more useful.

So far, the only non-standard dependency is curl (with OpenSSL or TLS support), so why not go install that while you wait? :)

Some other essential commands that should be present on any Linux distro:

* grep/egrep
* awk
* sed
* tr
