runnos = {'N54717','N54718','N54719','N54720','N54722','N54759','N54760','N54761','N54762','N54763', 'N54764','N54765','N54766','N54770','N54771','N54772','N54798','N54801','N54802','N54803','N54804','N54805','N54806','N54807','N54818','N54824','N54825','N54826','N54837','N54838','N54843','N54844','N54856','N54857','N54858','N54859','N54860','N54861','N54873','N54874','N54875','N54876','N54877','N54879','N54880','N54891','N54892','N54893','N54897','N54898','N54899','N54900','N54915','N54916','N54917'};

pathsifnos='/omega/';
pathpiper='/CivmUsers/';

sfid=fopen(['/Volumes/' pathsifnos 'CivmUsers/omega/alex/E3E4v1/copymyfiles.sh'],'w');
sfid=fopen(['/Volumes' pathsifnos 'omega/alex/E3E4v1/copymylabelsfiles.sh'],'w');
shebang='#!/bin/bash';
fprintf(sfid,'%s\n',shebang);


for i=1:numel(runnos)
    
   cmd1 = ['scp -r /Volumes/' pathsifnos '/omega/alex/E3E4v1/connect4dsistudio/pre_rigid_native_space/' runnos{i} '/' runnos{i} '_nii4D_RAS.nii.gz.src.gz.dti.fib.gz.fa_labels_warp_' runnos{i} '_RAS.count.pass.connectivity.mat ' ' /Volumes' pathsifnos 'omega/alex/E3E4v1/connectunthresh_seed/' runnos{i} '.mat'];
   fprintf(sfid,'%s;\n',cmd1);
% %     
   cmd2 = ['scp -r /Volumes/' pathsifnos '/omega/alex/E3E4v1/connect4dsistudio/pre_rigid_native_space/' runnos{i} '/' runnos{i} '_nii4D_RAS.nii.gz.src.gz.dti.fib.gz.fa_labels_warp_' runnos{i} '_RAS.count.pass.network_measures.txt ' ' /Volumes' pathsifnos 'omega/alex/E3E4v1/connectunthresh_seed/' runnos{i} 'network_measures.txt'];
   fprintf(sfid,'%s;\n',cmd2);
    
   cmd3= ['scp -r /Volumes/' pathsifnos '/omega/alex/E3E4v1/connect4dsistudio/pre_rigid_native_space/fa_labels_warp_' runnos{i} '_RAS.nii.gz ' ' /Volumes' pathsifnos 'omega/alex/E3E4v1/connectunthresh_Seed/' ];
   fprintf(sfid,'%s;\n',cmd3)
end
fclose(sfid)