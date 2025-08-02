Name:      ozo-znap-and-zhip
Version:   1.0.0
Release:   1%{?dist}
Summary:   automates the use of zfs send|receive
BuildArch: noarch

License:   GPL
Source0:   %{name}-%{version}.tar.gz

Requires:  bash

%description
This script automates the use of zfs send|receive to take and ship snapshots of ZFS file systems over SSH and performs snapshot maintenance. It also provides a means of creating ZFS filesystems on source systems and performing an origin (initial) snapshot that serves as the basis for all future incremental snapshots.
%prep
%setup -q

%install
rm -rf $RPM_BUILD_ROOT

mkdir -p $RPM_BUILD_ROOT/etc/cron.d
cp ozo-znap-and-zhip $RPM_BUILD_ROOT/etc/cron.d

mkdir -p $RPM_BUILD_ROOT/etc/ozo-znap-and-zhip.conf.d
cp ozo-znap-and-zhip-host.conf.example $RPM_BUILD_ROOT/etc/ozo-znap-and-zhip.conf.d

mkdir -p $RPM_BUILD_ROOT/usr/sbin
cp ozo-znap-and-zhip.sh $RPM_BUILD_ROOT/usr/sbin

%files
%attr (0644,root,root) %config(noreplace) /etc/cron.d/ozo-znap-and-zhip
%attr (0644,root,root) /etc/ozo-znap-and-zhip.conf.d/ozo-znap-and-zhip-host.conf.example
%attr (0700,root,root) /usr/sbin/ozo-znap-and-zhip.sh

%changelog
* Mon Mar 6 2023 One Zero One RPM Manager <repositories@onezeroone.dev> - 1.0.0-1
- Initial release
