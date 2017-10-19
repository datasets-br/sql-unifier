<?php
/**
 * Interpreter for datapackage (of FrictionLessData.io standards) and script (SH and SQL) generator.
 * Generate scripts at ./cache.
 *
 * USE: php src/pack2sql.php
 *
 * USING generated scripts:
 *     sh src/cache/makeTmp.sh
 *     PGPASSWORD=postgres psql -h localhost -U postgres lexvoc < src/cache/makeTmp.sql
 *
 */


$here = dirname(__FILE__); // ./src/php
$STEP = 3;
// CONFIGS at the project's conf.json
$conf = json_decode(file_get_contents($here.'/../../conf.json'),true);
$githubList = $conf['githublist'];
$useIDX =     $conf['useIDX'];    // false is real name, true is tmpcsv1, tmpcsv2, etc.
$useRename=   $conf['useRename']; // rename "ugly col. names" to ugly_col_names


// INITS:
$msg1 = "Script generated by datapackage.json files and pack2sql generator.";
$msg2 = "Created in ".substr(date("c", time()),0,10);
$IDX = 0;

$scriptSQL = "\n--\n-- $msg1\n-- $msg2\n--\n
	CREATE EXTENSION IF NOT EXISTS file_fdw;
	-- DROP SERVER IF EXISTS csv_files CASCADE; -- danger when using with other tools.
	CREATE SERVER csv_files FOREIGN DATA WRAPPER file_fdw;
";
$scriptSH  = "\n##\n## $msg1\n## $msg2\n##\n
	mkdir -p /tmp/tmpcsv
";

// MAIN:
fwrite(STDERR, "\n-------------\n BEGIN of cache-scripts generation\n");
fwrite(STDERR, "\n CONFIGS: useIDX=$useIDX, githubList=".count($githubList)." items.\n");

foreach($githubList as $prj=>$file) {
	//old if (ctype_digit((string) $prj)) list($prj,$file) = [$file,'_ALL_'];
	fwrite(STDERR, "\n Creating cache-scripts for $prj:");
	$urlBase = "https://raw.githubusercontent.com/$prj";
	$url = "$urlBase/master/datapackage.json";
	$pack = json_decode( file_get_contents($url), true );
	$test = [];
	$path = '';
	foreach ($pack['resources'] as $r) if (!$file || $r['name']==$file) {
		$path = $r['path'];
		$IDX++;
		fwrite(STDERR, "\n\t Building table$IDX with $path.");
		list($file2,$sql) = addSQL($r,$IDX);
		$scriptSQL .= $sql;
		$url = "$urlBase/master/$path";
		$scriptSH  .= "\nwget -O $file2 -c $url";
	} else
		$test[] = $r['name'];
	if (!$path)
		fwrite(STDERR, "\n\t ERROR, no name corresponding to '$file': ".join(", ",$test)."\n");
}

$cacheFolder = "$here/../cache";  // realpath()
if (! file_exists($cacheFolder)) mkdir($cacheFolder);
file_put_contents("$cacheFolder/step$STEP-1.sh", $scriptSH);
file_put_contents("$cacheFolder/step$STEP-2.sql", $scriptSQL);

fwrite(STDERR, "\n END of cache-scripts generation\n See makeTmp.* scripts at $cacheFolder\n");


// // //
// LIB

function pg_varname($s) {
	return strtolower( preg_replace('/[\s\-]+/s','_',$s) );
}

function pg_defcol($f) { // define a table-column
	$pgconv = ['integer'=>'integer','boolean'=>'boolean','number'=>'float','float'=>'float'];
	$name  = pg_varname($f['name']);
	$jtype = strtolower($f['type']);
	$pgtype = isset($pgconv[$jtype])? $pgconv[$jtype]: 'text';
	return [$name,$pgtype];
}

/**
 * Generates script based on FOREIGN TABLE, works fine with big-data CSV.
 */
function addSQL($r,$idx,$useConfs=true,$useAll=true,$useView=true) {
	global $useIDX;

	$p = $useIDX? "tmpcsc$idx": pg_varname( preg_replace('#^.+/|\.\w+$#','',$r['path']) );
	$table = $useIDX? $p: "tmpcsv_$p";
	$file = "/tmp/tmpcsv/$p.csv";

	$fields = [];
        $f2 = [];
        $f3 = [];
	$i=0;
	$fname_to_idx = []; // for keys only, not use aux_name
	foreach($r['schema']['fields'] as $f) {
		list($aux_name,$aux_pgtype) = pg_defcol($f);
		$fields[] = "$aux_name $aux_pgtype"; 
		$f2[] = $aux_name;
		$fname_to_idx[$f['name']] = $i;
		$f3[$i] = "(c->>$i)::$aux_pgtype AS $aux_name";
		$i++;
	}
	$usePk =false;
	$pk_order = 'id';
	$pk_cols = [];
	$pk_cols1 = [];
	$pk_names = [];
	if (isset($r['primaryKey'])) {
		$usePk = true;
		$pk_names = is_array($r['primaryKey'])? $r['primaryKey']: [$r['primaryKey']];
		foreach($pk_names as $n) {$pk_cols[] = $fname_to_idx[$n]; $pk_cols1[] = 1+$fname_to_idx[$n];}
		$pk_order = join(",",$pk_cols1);
	}
	$jsoninfo = pg_escape_string( json_encode($r,JSON_UNESCAPED_SLASHES|JSON_UNESCAPED_UNICODE) ); // check quotes
	$sql = '';
	if ($useConfs) $sql .= "
	   INSERT INTO dataset.confs(tmp_name,info) VALUES ('$p','$jsoninfo'::jsonb);
	  ";
	$sql .= "
	 DROP FOREIGN TABLE IF EXISTS $table CASCADE; -- danger drop VIEWS
	 CREATE FOREIGN TABLE $table (\n\t\t". join(",\n\t\t",$fields) ."
	  ) SERVER csv_files OPTIONS (
	     filename '$file',
	     format 'csv',
	     header 'true'
	  );
	";
	if ($useAll) {
	  $pkAtCols = $usePk? ",key": "";
	  $pkConcat = [];
	  foreach($pk_names as $n) $pkConcat[] = "$n::text";
	  $pkAtSel  = $usePk? (', concat('.join(",';',",$pkConcat).')'): "";
	  $sql .= "
	    INSERT INTO dataset.big(source$pkAtCols, c)
	      SELECT dataset.idconfig('$p') $pkAtSel, jsonb_build_array( ".join(', ',$f2)."   )
	      FROM tmpcsv_{$p};
	  ";
	}
	if ($useView) {
	  $vw = "dataset.vw_$p";
	  // falta ORDER BY x,y quando tem primary key  senao fazer 1,2,3.. conforme campos.
	  $sql .= "
	   DROP VIEW IF EXISTS $vw CASCADE; -- danger drop old dependents
	   CREATE VIEW $vw AS\n\t\tSELECT ". join(', ',$f3) ."\n\t\tFROM dataset.big where source=dataset.idconfig('$p') ORDER BY $pk_order;
	  ";
	}
	return [$file,$sql];
}
