---
layout: post
title: Erlang meets HANA
categories: hana
excerpt: How to connect Erlang with SAP HANA One using odbc
---
# {{ page.title }}

In this inaugural blog post we'll demonstrate how to connect [Erlang][erlang] and [SAP HANA One][hana_one] via [odbc][odbc].

## Prerequisites

### [SAP HANA One][hana_one]

You have successfully deployed an EC2 instance with [SAP HANA One][hana_one_setup].

![SAP HANA One Status]({{ site.url }}/assets/hana/HANA_One_Status.png)

### Erlang

I am using an Ubuntu EC2 instance with Erlang installed via the [prebuilt binaries][erlang_solutions_prebuilt] from [Erlang Solutions][erlang_solutions].

Install two dependent packages `libaio` and `unixodbc`.

{% highlight bash %}
weppner:~$ sudo aptitude install libaio unixodbc
{% endhighlight %}

## SAP HANA Client Libraries

Copy the download URL for your platform from the SAP HANA One Downloads section.

![SAP HANA One Download Section]({{ site.url }}/assets/hana/HANA_One_Downloads.png)

{% highlight bash %}
weppner:~/hana$ wget https://your_instance.compute.amazonaws.com/downloads/client/Rev62ClientLinux86_64.zip --no-check-certificate
weppner:~/hana$ unzip Rev62ClientLinux86_64.zip 
Archive:  Rev62ClientLinux86_64.zip
   creating: linuxx86_64/SAP_HANA_CLIENT/
   creating: linuxx86_64/SAP_HANA_CLIENT/client/
 extracting: linuxx86_64/SAP_HANA_CLIENT/client/CLIENTINST.TGZ  
  inflating: linuxx86_64/SAP_HANA_CLIENT/client/SQLDBC.TGZ  
 extracting: linuxx86_64/SAP_HANA_CLIENT/client/SAPSYSMF.TGZ  
  inflating: linuxx86_64/SAP_HANA_CLIENT/client/PYTHON.TGZ  
  inflating: linuxx86_64/SAP_HANA_CLIENT/client/PYDBAPI.TGZ  
  inflating: linuxx86_64/SAP_HANA_CLIENT/client/JDBC.TGZ  
  inflating: linuxx86_64/SAP_HANA_CLIENT/client/REPOTOOLS.TGZ  
  inflating: linuxx86_64/SAP_HANA_CLIENT/client/ODBC.TGZ  
  inflating: linuxx86_64/SAP_HANA_CLIENT/client/manifest  
  ...
  inflating: linuxx86_64/SAP_HANA_CLIENT/LABEL.ASC

weppner:~/hana$ cd linuxx86_64/SAP_HANA_CLIENT/
weppner:~/hana/linuxx86_64/SAP_HANA_CLIENT$ sudo ./hdbinst 

SAP HANA Database Client installation kit detected.


SAP HANA Database Installation Manager - Client Installation 1.00.62.380697
***************************************************************************


Enter Installation Path [/usr/sap/hdbclient]: 
Checking installation...
Preparing package "Python Runtime"...
Preparing package "Product Manifest"...
Preparing package "SQLDBC"...
Preparing package "REPOTOOLS"...
Preparing package "Python DB API"...
Preparing package "ODBC"...
Preparing package "JDBC"...
Preparing package "Client Installer"...
Installing SAP HANA Database Client to /usr/sap/hdbclient...
Installing package 'Python Runtime' ...
Installing package 'Product Manifest' ...
Installing package 'SQLDBC' ...
Installing package 'REPOTOOLS' ...
Installing package 'Python DB API' ...
Installing package 'ODBC' ...
Installing package 'JDBC' ...
Installing package 'Client Installer' ...
Installation done
Log file written to '/var/tmp/hdb_client_2013-09-13_06.14.39/hdbinst_client.log'.
{% endhighlight %}

## Configure SAP HANA Connection

### Securely Store Connection Details

`hdbuserstore` is part of the client libraries and can be used to store information about the host:port, user and password with a given `KEY`.

{% highlight bash %}
weppner:/usr/sap/hdbclient$ ./hdbuserstore set HDB your_instance.compute.amazonaws.com:30015 SYSTEM top_secret_password
{% endhighlight %}

### Test Connection

Before configuring `odbc`, let's test the connection with the _SAP HANA Database interactive terminal_ `hdbsql`. Use command `\s` to check the status.

{% highlight bash %}
weppner:/usr/sap/hdbclient$ ./hdbsql -U HDB

Welcome to the SAP HANA Database interactive terminal.
                                           
Type:  \h for help with commands          
       \q to quit                         

hdbsql=> \s
host          : hanaserver:30015
database      : HDB
user          : SYSTEM
kernel version: 1.00.62.380697
SQLDBC version: libSQLDBCHDB 1.00.62 Build 0380697-1510
autocommit    : ON
locale        : en_US.UTF-8
input encoding: UTF8

hdbsql HDB=> select 'hello HANA' from dummy
'hello HANA'
"hello HANA"
1 row selected (overall time 69.748 msec; server time 291 usec)
{% endhighlight %}

In a second test we can verify that `odbc` connectivity can also be established using `odbcreg`. Here, we refer to the `KEY` set using `hdbuserstore` above via the `@` notation.

{% highlight bash %}
weppner:/usr/sap/hdbclient$ ./odbcreg @HDB SYSTEM

ODBC Driver test.

Connect string: 'DSN=@HDB;UID=SYSTEM;'.
retcode:	 0
outString(38):	SERVERNODE={@HDB};DSN=@HDB;UID=SYSTEM;
Driver version SAP HDB 1.00 (2013-08-01).
Select now(): 2013-09-13 06:53:58.102000000 (29)
{% endhighlight %}

### Configure ODBC Driver and DSN

To enable other applications to use the `odbc` connection we edit `/etc/odbcinst.ini` to register the HANA `odbc` driver.

{% highlight ini %}
[HANA]
Description     = HANA driver for Linux
Driver          = /usr/sap/hdbclient/libodbcHDB.so
FileUsage       = 1
{% endhighlight %}

We now maintain a [DSN][dsn] in `/etc/odbc.ini` and again refer to the `KEY` set in `hdbuserstore` as well as the driver name registered above.

{% highlight ini %}
[HDB]
SERVERNODE=@HDB
DRIVER=HANA
CHAR_AS_UTF8=true
{% endhighlight %}

## Connect from Erlang

Let's create an Erlang module `hana_marries_erlang.erl` to demonstrate how to connect and issue an SQL statement using Erlang's [odbc module](http://www.erlang.org/doc/man/odbc.html)

{% highlight erlang linenos %}
-module(hana_marries_erlang).
-export([connect/0, disconnect/1, command/2]).

% Basic database connectivity
connect()->
  odbc:start(),
  {ok, Connection} = odbc:connect("DSN=HDB",[]),
  Connection.

% SQL command
command(Connection, Sql)->
  odbc:sql_query(Connection, Sql).

% Disconnect
disconnect(Connection)->
  odbc:disconnect(Connection).
{% endhighlight %}

Using an Erlang shell we can finally ask [SAP HANA][hana] some serious questions.

{% highlight erl %}
Erlang R16B01 (erts-5.10.2) [source-bdf5300] [64-bit] [async-threads:10] [hipe] [kernel-poll:false]

Eshell V5.10.2  (abort with ^G)
1> c(hana_marries_erlang).
{ok,hana_marries_erlang}
2> C = hana_marries_erlang:connect().
<0.45.0>
3> hana_marries_erlang:command(C, "select 'Will you marry me?' from dummy").
{selected,["'Will you marry me?'"],[{"Will you marry me?"}]}
4> hana_marries_erlang:disconnect(C).
ok
{% endhighlight %}

[erlang]: http://www.erlang.org
[erlang_solutions]: https://www.erlang-solutions.com
[erlang_solutions_prebuilt]: https://www.erlang-solutions.com/downloads/download-erlang-otp
[hana]: http://help.sap.com/hana
[hana_one]: http://help.sap.com/hana_one
[hana_one_setup]: http://www.saphana.com/docs/DOC-2437
[odbc]: http://en.wikipedia.org/wiki/odbc
[dsn]: http://en.wikipedia.org/wiki/Data_Source_Name