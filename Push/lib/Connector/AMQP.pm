# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Connector::AMQP;

use strict;
use warnings;

use base 'Bugzilla::Extension::Push::Connector::Base';

use Bugzilla::Constants;
use Bugzilla::Extension::Push::Constants;
use Bugzilla::Extension::Push::Util;
use Bugzilla::Util qw(generate_random_password);
use DateTime;
use Net::RabbitMQ;

sub init {
    my ($self) = @_;
    $self->{mq} = 0;
    $self->{channel} = 1;

    if ($self->config->{queue}) {
        $self->{queue_name} = $self->config->{queue};
    } else {
        my $queue_name = Bugzilla->params->{'urlbase'};
        $queue_name =~ s#^https?://##;
        $queue_name =~ s#/$#|#;
        $queue_name .= generate_random_password(16);
        $self->{queue_name} = $queue_name;
    }
}

sub options {
    return (
        {
            name     => 'host',
            label    => 'AMQP Hostname',
            type     => 'string',
            default  => 'localhost',
            required => 1,
        },
        {
            name     => 'port',
            label    => 'AMQP Port',
            type     => 'string',
            default  => '5672',
            required => 1,
            validate => sub {
                $_[0] =~ /\D/ && die "Invalid port (must be numeric)\n";
            },
        },
        {
            name     => 'username',
            label    => 'Username',
            type     => 'string',
            default  => 'guest',
            required => 1,
        },
        {
            name     => 'password',
            label    => 'Password',
            type     => 'string',
            default  => 'guest',
            required => 1,
        },
        {
            name     => 'vhost',
            label    => 'Virtual Host',
            type     => 'string',
            default  => '/',
            required => 1,
        },
        {
            name     => 'exchange',
            label    => 'Exchange',
            type     => 'string',
            default  => '',
            required => 1,
        },
        {
            name     => 'queue',
            label    => 'Queue',
            type     => 'string',
        },
    );
}

sub stop {
    my ($self) = @_;
    if ($self->{mq}) {
        Bugzilla->push_ext->logger->debug('AMQP: disconnecting');
        $self->{mq}->disconnect();
        $self->{mq} = 0;
    }
}

sub _connect {
    my ($self) = @_;
    my $logger = Bugzilla->push_ext->logger;
    my $config = $self->config;

    $self->stop();

    $logger->debug('AMQP: Connecting to RabbitMQ ' . $config->{host} . ':' . $config->{port});
    my $mq = Net::RabbitMQ->new();
    $mq->connect(
        $config->{host},
        {
            port => $config->{port},
            user => $config->{username},
            password => $config->{password},
        }
    );
    $self->{mq} = $mq;

    $logger->debug('AMQP: Opening channel ' . $self->{channel});
    $self->{mq}->channel_open($self->{channel});

    $logger->debug('AMQP: Declaring queue ' . $self->{queue_name});
    $self->{mq}->queue_declare(
        $self->{channel},
        $self->{queue_name},
        {
            passive     => 0,
            durable     => 1,
            exclusive   => 0,
            auto_delete => 0,
        },
    );
}

sub _bind {
    my ($self, $message) = @_;
    my $logger = Bugzilla->push_ext->logger;
    my $config = $self->config;

    # bind to queue (also acts to verify the connection is still valid)
    if ($self->{mq}) {
        eval {
            $logger->debug('AMQP: binding queue(' . $self->{queue_name} . ') with exchange(' . $config->{exchange} . ')');
            $self->{mq}->queue_bind(
                $self->{channel},
                $self->{queue_name},
                $config->{exchange},
                $message->routing_key,
                'routing_key'
            );
        };
        if ($@) {
            $logger->debug('AMQP: ' . clean_error($@));
            $self->{mq} = 0;
        }
    }

}

sub send {
    my ($self, $message) = @_;
    my $logger = Bugzilla->push_ext->logger;
    my $config = $self->config;

    $self->_bind($message);

    eval {
        # reconnect if required
        if (!$self->{mq}) {
            $self->_connect();
        }

        # send message
        $logger->debug('AMQP: Publishing message');
        $self->{mq}->publish(
            $self->{channel},
            $message->routing_key,
            $message->payload,
            {
                exchange => $config->{exchange},
            },
            {
                content_type => 'text/plain',
                content_encoding => '8bit',
            },
        );
    };
    if ($@) {
        return (PUSH_RESULT_TRANSIENT, clean_error($@));
    }

    return PUSH_RESULT_OK;
}

1;
