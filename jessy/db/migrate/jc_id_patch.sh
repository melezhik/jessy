mysql -h mysql3.adriver.x -ujessy -pjessy jessy -sNe 'select id from builds where jc_id is null order by id asc ' | perl -n -e 'chomp; print qq{ mysql -h mysql3.adriver.x -ujc -pjc jc -sNe \"select key_id, id from builds where key_id = $_\" \n } ' | bash | perl -n -e 'chomp; ($key_id,$jc_id) = split;  $a =  `curl -s -f -L pinto.webdev.x:4000/builds/$jc_id` ; print qq{  mysql -h mysql3.adriver.x -ujessy -pjessy jessy -sNe \" update builds set jc_id = $jc_id where jc_id is null and id = $key_id  \" # $a } ' 
