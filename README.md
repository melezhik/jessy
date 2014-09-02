# Synopsis

Jessy is the pinto based build server for perl applications.

# Features
* creates perl applications builds 
* uses [pinto](https://github.com/thaljef/Pinto) inside to handle dependencies
* supports subversion and git SCMs
* both Makefile.PL, Build.PL systems support 
* asynchronously executes build tasks
* sends builds notifications by jabber
* keeps artefacts
* shows differences between builds
* show project activity logs
* this is a ruby on rails application


# Installation

    su - jessy
    git git@git.x:melezhik/jessy.git
    cd jessy/jessy
    bundle install # install ruby dependencies
    eye load config/eye/app.rb


# Prerequisites
- nodejs
- libmysql 

# Pinto repository root directory

Will be created in $HOME/.jessy/repo directory. To migrate existed one simply run following:

    mkdir -p  $HOME/.jessy/repo/ && cp -r /path/to/existed/repo/root  $HOME/.jessy/repo

# Gory details

This is a concise explanation of jessy object model.
 
## jessy 

Is a name of the build server. jessy-on-rails - a long, "official" name, bear in mind that jessy application is written on ruby on rails framework.

## Application

Is arbitruary perl application. 

## Component

Is a part of application, an arbitrary source code stored in VCS. In jessy model an application is the _list_ of components.  Components may also be treated as perl modules, but not necessarily should be perl modules. Every component should has valid Build.PL|Makefile.PL file, placed at component's root directory in VCS.

## jessy dependency

This is the one of two types of things:

- a __CPAN module__ - get resolved from cpan repository;
- a __component__; a components of course may depend on CPAN modules

## jessy project  

Is an application _view_ in jessy GUI.

## Build proccess 

The process of creation of distribution archive for an application. Schematically it may be described as following:

### Pinto phase

- every component in application list is visited and converted into pinto distirbution archive and then is added to pinto repository - this is called __pinto phase__.

### Compile phase

- when pinto phase is finished, every component's distribution achive is fetched from pinto repository and installed into local directory - __build install base__ - this is called __compile phase__.

### Creating of artefacts

- if pinto phase is finshed successfully then build install base is archived, archived build install base called __build artefact__.

## jessy build

Build is the "snapshot" of application plus some build's data. 

When the build starts project's components list is copied to build. The list of builds components is called __build configuration__.

### Build data
The three type of things:
- an __install base__ - local directory with all of the application dependencies.
- an 'attached' __pinto stack__, which represents all module's versions installed into build install base.
- a __build state__ - the build state, on of the following: `schedulled|processing|succeeded|failed`. Succeeded build state means build process has finished successfully and build has a artefact.

## Sequences of builds

This mechanism is described as  folows. User changes an application component's list and initiates the build processes resulting in build sequences for given project.  Different builds in the sequence may be compared. 

## Build "inheritance" 

The term of build inheritance may be described as follows. When build process starts:

- new pinto stack is created as a copy of pinto stack for previous build
- new install base is created as a copy of install base for previous build
- new build process is scheduled and build is added to builds queue ( see note about build scheduler )

## Build scheduler 

Is the asynchronous scheduler which processes the builds queue. Build schediler uses delayed_job under the hood.


# RESTfull API

Here I "drop" some common actions which may be done with restfull api as well

## run build


    curl -X POST http://127.0.0.1/projects/<project-id>/builds -d '' -f -o /dev/null

- __project-id__  - the project ID where you want to run build 


## copy build from one project to another project 


    curl -X POST http://127.0.0.1/projects/<project-id>/builds/<build-id>/revert -d '' -f -o /dev/null


- __build-id__    - the build ID which you want to copy 
- __project-id__  - the project ID where you want to copy build to


# PERL5LIB

- You may setup $PERL5LIB variable via jessy/settings/ page. jessy will add PERL5LIB both to pinto and compile phases.

- Also be noticed, that jessy add $HOME/lib/perl5 to $PERL5LIB during pinto phase. That may be usefull when one want to use (Module::Build, ExtUtils::MakeMaker or Module::Install ) which installed locally.


# See also
- [jc](https://git.x/melezhik/jc/tree/master)
- [pinto](https://github.com/thaljef/Pinto)
- [ruby on rails](http://rubyonrails.org)
- [delayed job](https://github.com/collectiveidea/delayed_job)

