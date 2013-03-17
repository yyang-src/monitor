#!/bin/sh

crontab -l -urealworx > /sunrise/bkup/crontab.realworx.out
crontab -l > /sunrise/bkup/crontab.root.out
