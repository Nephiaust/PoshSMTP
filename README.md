# PoshSMTP
A really stupid idea of implementing a SMTP service in PowerShell.

## Requirements
* Windows PowerShell 5.1; OR
* PowerShell 6+
* Linux, MacOS, Windows (currently supported)

## Goals
* Learn how SMTP services work (SMTPD, MTA, SMTPC)
* See if it can be implemented in PowerShell, including security
* Be able to run on the internet as an actual relay / server

## To do
* Implement receiving emails. Have the basic framework started for the base commands
* Implement threading. Currently dont know how to start a new thread and share the TCP & Logging objects to the new thread.
* Implement security (the EHLO)
* Implement mailboxes
