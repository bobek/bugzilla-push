# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push;

use strict;

use constant NAME => 'Push';

use constant REQUIRED_MODULES => [
    {
        package => 'Daemon-Generic',
        module  => 'Daemon::Generic',
        version => '0'
    },
    {
        package => 'JSON-XS',
        module  => 'JSON::XS',
        version => '2.0'
    },
    {
        package => 'Net--RabbitMQ',
        module  => 'Net::RabbitMQ',
        version => '0'
    },
    {
        package => 'POE',
        module  => 'POE',
        version => '0'
    },
];

use constant OPTIONAL_MODULES => [ ];

__PACKAGE__->NAME;
