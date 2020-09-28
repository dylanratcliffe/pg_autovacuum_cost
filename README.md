# Postgres Vacuum Cost Limit Stats

#### tl;dr

If you feel super lazy don't even use this tool. Just set this in `postgresql.conf`:

```ini
# 10x the default limit.
#
# If this causes problems or is for something
# critical/prodution: Do proper research
autovacuum_vacuum_cost_limit = 2000
```

## The story of Craig the autovacuum worker 🧑‍🔧

Think of your Postgres database as a movie theater. You've got a bunch of individual cinemas (tables), and lots of patrons coming and going (rows) and leaving popcorn crumbs everywhere (dead tuples). A critical part of an efficient cinema is vacuuming up all the popcorn once someone leaves so that the next person can use that seat. This job is done by the autovacuum workers. Since you have a small cinema you have one worker and his name is Craig.

Craig decides when it is time to vacuum a specific cinema by looking at how many people have come and gone and estimating how many seats must at this point have popcorn on them. If this percentage is greater than `autovacuum_vacuum_scale_factor` then he will start vacuuming that particular cinema.

As your cinema gets more popular Craig is going to get busier and busier to a point where at some point he isn't going to be able to keep up. Fortunately the management has a good solution to keep the patrons coming in: More seats! A new policy is enacted that if a patron comes in and there aren't any clean seats, we build them a new seat and just keep expanding the cinema. Problem solved! Management doesn't care if we're expanding the cinema because there aren't enough *total* seats, or because there aren't enough *clean* seats, they just add more seats.

Also part of this new policy is that once we've added a seat we never get rid of it again. It's too much hassle to get rid of a seat, only to build a new one if you happen to need it again. That makes sense right...?

**Note:** The above is the reason why Postgres databases never get smaller even if you delete all the data in it. In this case building the seats means requesting disk space from the OS. But it's true that it takes a really long time compared to using disk space you already have, and it actually doesn't ever give it back (except in a VACUUM FULL, or a drop table)

With this new policy it means that nobody ever has to wait for Craig to clean the seat before they can sit down, if there aren't any clean ones they just get a new seat.

A week goes by and things are great. Craig is busy as hell, and he isn't actually cleaning seats faster than new ones are getting popcorn on them overall. But he does manage to clean a few cinemas and even though since it takes him longer and longer to clean each cinema, and the cinemas are getting larger and larger, with more and more dirty chairs he loves his job so he doesn't complain.

However after another few weeks management start to notice that the cinema really is starting to get awfully big, and they aren't actually serving any more patrons. They realise that they are going to have to solve their cleaning problem. To this they weigh up two options:

1. **Allow Craig's vacuum cleaner to draw more power:** This will mean that Craig can work faster, but we'll have to be careful. If we let him draw too much power he will literally clean so fast there is no power for the cinema to run. He **really** loves his job. It'll be clean as hell, but wee don't really want all the projectors to switch off when Craig decides to clean a cinema at lightspeed
1. **Hire more workers:** This seems like the obvious choice, but all the workers share the same power limit for their vacuuming, so it will just mean that all of them work slower unless we also increase the power limit.

Despite their previous record for poor management decisions with the whole "add more chairs" debacle, management actually make a good decision here. They do both! firstly they increase the amount of power that vacuum cleaners can draw by 10x (`autovacuum_vacuum_cost_limit`) since they realised that their first limits were way too low. They also realised however that sometimes Craig has other things to do than vacuuming. Sometimes he has to wait for people to get out of the way and he does have to take bathroom breaks. So they also hired two more staff to ensure that all of this new power limits can be utilised even if Craig is stuck doing something else.

**Summary:** Hopefully this explains the purpose of `autovacuum_vacuum_cost_limit` and why it's important. While the other settings like the number of workers, and the settings that regulate when/how often a vacuum should be triggered can help to optimise the vacuuming process, but the reality is that no amount of tuning these parameters can help if you're in a situation where you are cleaning popcorn slower then it's coming in. The ultimate purpose of this tool is to tell if whether or not you are in that position

Further reading:

* https://www.datadoghq.com/blog/postgresql-vacuum-monitoring
* https://www.2ndquadrant.com/en/blog/autovacuum-tuning-basics

## Usage

Run the tool against the logs:

```shell
ruby vacuum.rb /var/log/postgresql/**/postgresql-*.log > results.csv
```

Now have a look results in your favorite CSV viewer! The columns are as follows:

**Day:** The day for which the results are aggregated

**Number of Log Entries:** How many times autovacuum logged that it completed that day

**Total Vacuuming Time (s):** The total amount of time in seconds spent vacuuming in thais day. Note this can be greater than 86,400 because there are usually many workers

**Vacuum Load Average:** 💥 THIS IS THE IMPORTANT METRIC 💥. This is the average number of workers who are vacuuming at any given point.  The closer this number is to the `autovacuum_max_workers`, the more saturated they are. If you have 3 workers and this number is > 2.7 you're in trouble and you need to increase `autovacuum_vacuum_cost_limit` and possibly also `autovacuum_max_workers`. Note that it is possible for workers to be stuck due to locking and not because they don't have enough `autovacuum_vacuum_cost_limit` but even with the default number of three workers I've never seen this be a problem.

**Total Removed Tuples:** Total tuples removed during that day

**Total Buffer Hits:** A buffer hit is when the worker found the data is was looking for in the postgres buffer, meaning that it didn't have to read from disk

**Total Buffer Misses:** A buffer miss is when the worker couldn't the data is was looking for in the postgres buffer, meaning that it might have been read from disk. Or maybe the OS cached it.

**Total Buffer Dirtied:** This is when the worker had to do a write to disk

**Average Read Rate (MB/s):** Average read rate of all workers combined

**Average Write Rate (MB/s):** Average write rate of all workers combined
